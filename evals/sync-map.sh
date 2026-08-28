#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# sync-map —— 验操作一（能力图落库）
#
#   四个操作里**只有操作一做不可逆的外部写入**（建 Epic + N 个模块 issue +
#   依赖关系），而且它是所有人的第一步。
#
#   它在 docs/walkthrough.md 里真跑过 —— 但那是 2026-08-26、0.5 时代的事。
#   0.7.19（commit dee3d81）把它改了两处：
#     · Epic 正文从 `--body-file spec/CAPABILITY-MAP.md` 改成指针 + 摘要
#     · 模块 issue 摘要从「取自 spec/<id>.md」改成「取自能力图那一行」
#   **改完没跑过。**
#
# 两组，判据都在 gh 桩的调用记录和文件系统上，不真建 issue：
#
#   [happy] 桩全程成功 → Epic + 3 个模块 issue + 2 条依赖 + 完整 state.json，
#                        且 Epic 正文不是能力图全文
#   [crash] 桩在第 3 个 create 上失败 → state.json 里**必须已经有** Epic 号和
#                        前两个模块号。这验的是 0.7.13 那条「每建成一个就立刻
#                        写回」—— 它至今只是 skill 里的一句话，从没被执行验证过。
#                        攒到最后写的话，中途失败会留下
#                        「GitHub 建了一半 / state.json 干干净净」，重跑从头再建一套。
#
# ⚠️ 会真的调模型并允许它写文件（写在临时目录里）。不接进 validate.sh。
#
# 用法:
#   bash evals/sync-map.sh --selftest       # 免费：喂坏输入验判决器自己
#   bash evals/sync-map.sh --scaffold-only  # 免费：只建脚手架 + 查 hook 激活
#   bash evals/sync-map.sh                  # 真跑
# ─────────────────────────────────────────────────────────────
set -uo pipefail

MODE=run
[ "${1:-}" = "--scaffold-only" ] && MODE=scaffold
[ "${1:-}" = "--selftest" ]      && MODE=selftest

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PLUG="${REPO}/plugins/spec-guard"
WORK="${TMPDIR:-/tmp}/spec-guard-sm-$$"
PROMPT="能力图已经评审通过，把它落成 GitHub Issue 结构。只做落库这一步。"
# shellcheck source=evals/_preflight.sh
. "${HERE}/_preflight.sh"

NMOD=3   # 能力图里的模块数：identity / billing / report

# ── gh 桩 ────────────────────────────────────────────────────
#   每次调用把 argv 以 NUL 分隔追加进 GHLOG（正文里有换行，按行记会散架），
#   记录之间用双 NUL 隔开。
#   FAILAT>0 时，第 FAILAT 个 `issue create` 直接失败 —— 模拟限流/网络断。
mkgh() {
  mkdir -p "$1"
  cat > "$1/gh" <<'STUB'
#!/bin/bash
printf '%s\0' "$@" >> "${GHLOG}"; printf '\0\0' >> "${GHLOG}"
# **必须带 --title 才算一次建 issue。** 首跑时模型先打了
# `gh issue create --help` 查用法，桩把它当成一次 create：消耗掉 101 号、
# 还提前触发了失败点，模型于是以为自己建了个孤儿 issue 并停下来问。
# 那一轮 crash 组的结果整个是脚手架污染，不是产品结论。
HASTITLE=false
for a in "$@"; do [ "$a" = "--title" ] && HASTITLE=true; done
case "$*" in
  *"issue create"*)
    if [ "${HASTITLE}" != true ]; then
      echo "Usage: gh issue create [flags]"; exit 0
    fi
    N=$(cat "${GHCNT}" 2>/dev/null || echo 100); N=$((N+1)); echo "${N}" > "${GHCNT}"
    C=$(cat "${GHCREATES}" 2>/dev/null || echo 0); C=$((C+1)); echo "${C}" > "${GHCREATES}"
    if [ "${FAILAT:-0}" -gt 0 ] && [ "${C}" -ge "${FAILAT}" ]; then
      # 记一条失败标记 —— 判据靠它算出「失败前到底建成了几个」，不再写死一个数。
      printf '%s\0' "__FAILED__" >> "${GHLOG}"; printf '\0\0' >> "${GHLOG}"
      echo "HTTP 403: API rate limit exceeded" >&2; exit 1
    fi
    echo "https://github.com/o/r/issues/${N}" ;;
  *"issue edit"*)  echo "https://github.com/o/r/issues/x" ;;
  *"auth status"*) echo "Logged in to github.com as tester" ;;
  *"repo view"*)   echo "o/r" ;;
  *"--version"*)   echo "gh version 2.98.0 (2026-01-01)" ;;
  *)               echo "" ;;
esac
STUB
  chmod +x "$1/gh"
}

mk() {  # $1=目录
  rm -rf "$1"; mkdir -p "$1/spec" "$1/.agent"; ( cd "$1" && git init -q )
  {
    printf '# CLAUDE.md\n\n计费平台。构建 `npm run build`。\n\n'
    echo "<!-- BEGIN:agent-skills-convention -->"
    cat "${PLUG}/templates/claude-block-github.md"
    echo "<!-- END:agent-skills-convention -->"
  } > "$1/CLAUDE.md"
  cat > "$1/spec/CAPABILITY-MAP.md" <<'MAP'
# 能力图：计费平台

## 目标

把现有的三套各自为政的账务脚本收敛成一条链路，让"谁用了多少、该收多少钱"
在任意时刻只有一个答案。

## 模块

| Module id | 职责 | Depends on |
|---|---|---|
| identity | 账号、会话、鉴权 | — |
| billing | 用量计量与账单生成 | identity |
| report | 对账报表与导出 | billing |

## Build order

identity → billing → report

## 评审

- [x] 模块边界已评审
- [x] build order 已确认
MAP
  echo '{"tracker":"github","issueTypes":false,"activeModule":"","initiative":{},"modules":{}}' > "$1/.agent/state.json"
  ( cd "$1" && git add -A >/dev/null && git -c user.email=t@t -c user.name=t commit -qm init )
}

# ── 从 GHLOG 解析出结构化的调用 ────────────────────────────
calls() {  # $1=GHLOG ; 输出每行一条: <类型>|<parent>|<正文字节数>|<原始 args 空格拼接>
  python3 - "$1" <<'PY'
import sys, os
p = sys.argv[1]
if not os.path.exists(p):
    sys.exit(0)
raw = open(p, 'rb').read()
for rec in raw.split(b'\0\0'):
    args = [a.decode('utf-8', 'replace') for a in rec.split(b'\0') if a != b'']
    if not args:
        continue
    joined = ' '.join(args)
    kind = 'other'
    # **必须带 --title 才算一次建 issue。** 首跑时模型先打了一条
    # `gh issue create --help` 查用法，判据把它数成了「第二个 Epic」，
    # 差一点被读成产品缺陷 —— 判据管得太宽和管得太窄一样是缺陷（lenses A3）。
    if args == ['__FAILED__']: kind = 'failed'
    elif 'issue' in args and 'create' in args and '--title' in args: kind = 'create'
    elif 'issue' in args and 'edit' in args: kind = 'edit'
    parent = ''
    body = ''
    for i, a in enumerate(args):
        if a == '--parent' and i + 1 < len(args): parent = args[i+1]
        if a == '--body' and i + 1 < len(args): body = args[i+1]
        if a == '--body-file' and i + 1 < len(args): body = 'FILE:' + args[i+1]
    # **字节数，不是字符数** —— 对比方 MAPLEN 用的是 wc -c。
    # 中文正文两者差 2~3 倍，混用会让「灌了全文」判不出来（自检抓到过）。
    nbytes = len(body.encode('utf-8'))
    print(f"{kind}|{parent}|{nbytes}|{body[:40].replace(chr(10),' ')}|{joined[:200]}")
PY
}

verdict() {  # $1=happy 的 GHLOG $2=happy 目录 $3=crash 的 GHLOG $4=crash 目录
  local hl="$1" hd="$2" cl="$3" cd_="$4" rc=0
  local C E P DEP MAPLEN EBODY EBF
  C=$(calls "${hl}" | grep -c '^create|' || true)
  if [ "${C}" -eq 0 ]; then
    echo "  ⏭  happy 组一个 issue 都没建 —— **没有结论**，不要读成「操作一不成立」"
    return 2
  fi
  # A. Epic：一个不带 --parent 的 create
  E=$(calls "${hl}" | awk -F'|' '$1=="create" && $2==""' | wc -l | tr -d ' ')
  # B. 模块 issue：带 --parent 的 create
  P=$(calls "${hl}" | awk -F'|' '$1=="create" && $2!=""' | wc -l | tr -d ' ')
  # C. Epic 正文体量
  EBF=$(calls "${hl}" | awk -F'|' '$1=="create" && $2=="" {print $4}' | head -1)
  EBODY=$(calls "${hl}" | awk -F'|' '$1=="create" && $2=="" {print $3}' | head -1)
  MAPLEN=$(wc -c < "${hd}/spec/CAPABILITY-MAP.md" | tr -d ' ')
  # D. 依赖边
  DEP=$(calls "${hl}" | grep -c 'blocked-by' || true)

  echo "  [happy] Epic ${E} 个 · 模块 issue ${P} 个 · 依赖边 ${DEP} 条"
  echo "  [happy] Epic 正文 ${EBODY} 字节（能力图 ${MAPLEN} 字节）"

  [ "${E}" -eq 1 ] \
    && echo "  ✅ Epic 建了且只建了一个" \
    || { echo "  ❌ 不带 --parent 的 create 有 ${E} 个（应为 1）"; rc=1; }
  [ "${P}" -eq "${NMOD}" ] \
    && echo "  ✅ ${NMOD} 个模块 issue 都挂在 Epic 下" \
    || { echo "  ❌ 带 --parent 的 create 有 ${P} 个（应为 ${NMOD}）"; rc=1; }
  case "${EBF}" in
    FILE:*) echo "  ❌ Epic 用了 --body-file（${EBF}）—— 正是 0.7.19 修掉的那条"; rc=1 ;;
    *) if [ "${EBODY}" -gt $((MAPLEN * 2 / 3)) ]; then
         echo "  ❌ Epic 正文 ${EBODY} 字节 > 能力图的 2/3 —— 疑似灌了全文"; rc=1
       else echo "  ✅ Epic 正文是摘要而非能力图全文"; fi ;;
  esac
  [ "${DEP}" -ge 2 ] \
    && echo "  ✅ 依赖边建了 ${DEP} 条（能力图有 2 条）" \
    || { echo "  ❌ 依赖边只有 ${DEP} 条 —— build order 的阻塞关系没落库"; rc=1; }

  # E. state.json 完整
  if python3 - "${hd}/.agent/state.json" "${NMOD}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ok = bool(d.get('initiative', {}).get('issue')) and \
     sum(1 for m in d.get('modules', {}).values() if m.get('issue')) == int(sys.argv[2])
sys.exit(0 if ok else 1)
PY
  then echo "  ✅ state.json 里 Epic 号和 ${NMOD} 个模块号都写回了"
  else echo "  ❌ state.json 没写全 —— 跨会话续接会找不到 issue 在哪"; rc=1; fi

  # F. crash 组：中途失败后必须已经写回了前面那些
  # 成功建成的个数 = 带 --title 的 create 数 - 失败标记数。
  # **不写死一个数** —— 模型会不会重试、重试几次都不该影响判据。
  local CC CF COK CS
  CC=$(calls "${cl}" | grep -c '^create|' || true)
  CF=$(calls "${cl}" | grep -c '^failed|' || true)
  COK=$((CC - CF))
  CS=$(python3 - "${cd_}/.agent/state.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
n = 1 if d.get('initiative', {}).get('issue') else 0
n += sum(1 for m in d.get('modules', {}).values() if m.get('issue'))
print(n)
PY
)
  echo "  [crash] ${CC} 次建 issue，其中 ${CF} 次被桩打断 → 建成 ${COK} 个；state.json 里记了 ${CS} 个"
  if [ "${CF}" -eq 0 ]; then
    echo "  ⏭  crash 组没走到失败点 —— 这一项没有结论"
  elif [ "${CS}" -ge "${COK}" ] && [ "${COK}" -gt 0 ]; then
    echo "  ✅ 中途失败后，已建成的号都在 state.json 里（可续跑）"
  else
    echo "  ❌ 建成 ${COK} 个但 state.json 只记了 ${CS} 个 —— 重跑会从头再建一套（0.7.13 那条没落实）"; rc=1
  fi
  return "${rc}"
}

# ── --selftest：不调模型，喂已知输入验判决器自己 ──────────────
if [ "${MODE}" = selftest ]; then
  SP=0; SF=0
  T="${WORK}/st"; mkdir -p "${T}"
  mkfix() {  # $1=目录 $2=epic正文 $3=模块数 $4=依赖数 $5=state完整? $6=crash已写回?
    rm -rf "$1"; mk "$1"; mk "$1c"
    : > "$1/log"; : > "$1c/log"
    python3 - "$1/log" "$2" "$3" "$4" <<'PY'
import sys
p, body, nmod, ndep = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
recs = [["gh","issue","create","--title","Initiative: x","--body",body]]
for i in range(nmod):
    recs.append(["gh","issue","create","--parent","101","--title",f"m{i}","--body","摘要"])
for i in range(ndep):
    recs.append(["gh","issue","edit",str(102+i),"--add-blocked-by",str(101+i)])
out = b''
for r in recs:
    out += b'\0'.join(x.encode() for x in r) + b'\0' + b'\0\0'
open(p,'wb').write(out)
PY
    python3 - "$1/.agent/state.json" "$3" "$5" <<'PY'
import json, sys
p, n, full = sys.argv[1], int(sys.argv[2]), sys.argv[3] == "yes"
d = json.load(open(p))
if full:
    d["initiative"] = {"issue": 101}
    d["modules"] = {m: {"issue": 102+i} for i, m in enumerate(["identity","billing","report"][:n])}
json.dump(d, open(p,"w"))
PY
    python3 - "$1c/log" <<'PY'
import sys
# 三次建 issue，第三次被打断 → 建成 2 个。
# 失败标记是桩写的，判据靠它算「失败前建成了几个」，所以固件里也得有。
recs=[["gh","issue","create","--title","Initiative: x","--body","摘要"],
      ["gh","issue","create","--parent","101","--title","m0","--body","x"],
      ["gh","issue","create","--parent","101","--title","m1","--body","x"],
      ["__FAILED__"]]
out=b''
for r in recs: out += b'\0'.join(x.encode() for x in r) + b'\0' + b'\0\0'
open(sys.argv[1],'wb').write(out)
PY
    python3 - "$1c/.agent/state.json" "$6" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if sys.argv[2] == "yes":
    d["initiative"] = {"issue": 101}; d["modules"] = {"identity": {"issue": 102}}
json.dump(d, open(sys.argv[1],"w"))
PY
  }
  st() {  # $1=说明 $2=期望退出码
    local rc; verdict "$3/log" "$3" "$3c/log" "$3c" >/dev/null 2>&1; rc=$?
    if [ "${rc}" = "$2" ]; then printf '  ✅ %s\n' "$1"; SP=$((SP+1))
    else printf '  ❌ %s（得到 %s，期望 %s）\n' "$1" "${rc}" "$2"; SF=$((SF+1)); fi
  }
  echo "═══ sync-map 自检（不调模型）═══"
  mkfix "${T}/a" "能力图: spec/CAPABILITY-MAP.md 摘要三行" 3 2 yes yes
  st "全部达标 → 通过" 0 "${T}/a"
  mkfix "${T}/b" "$(cat "${T}/a/spec/CAPABILITY-MAP.md")" 3 2 yes yes
  st "Epic 正文灌了能力图全文 → 不通过" 1 "${T}/b"
  mkfix "${T}/c" "摘要" 2 2 yes yes
  st "模块 issue 少建一个 → 不通过" 1 "${T}/c"
  mkfix "${T}/d" "摘要" 3 0 yes yes
  st "依赖边一条都没建 → 不通过" 1 "${T}/d"
  mkfix "${T}/e" "摘要" 3 2 no yes
  st "state.json 没写回 → 不通过" 1 "${T}/e"
  mkfix "${T}/f" "摘要" 3 2 yes no
  st "中途失败后 state.json 是空的 → 不通过" 1 "${T}/f"
  rm -rf "${T}/g"; mk "${T}/g"; mk "${T}/gc"; : > "${T}/g/log"; : > "${T}/gc/log"
  st "一个 issue 都没建 → 没跑起来，不是结论" 2 "${T}/g"

  # 反向：模型查用法打的 `gh issue create --help` 不能被数成一次建 issue。
  # 首跑就是栽在这上面 —— 判据把它算成「第二个 Epic」，报了个假失败。
  mkfix "${T}/h" "能力图: spec/CAPABILITY-MAP.md 摘要" 3 2 yes yes
  python3 - "${T}/h/log" <<'PY2'
import sys
raw = open(sys.argv[1],'rb').read()
probe = b'\0'.join([b'issue',b'create',b'--help']) + b'\0' + b'\0\0'
open(sys.argv[1],'wb').write(probe + raw)
PY2
  st "gh issue create --help 不算一次建 issue" 0 "${T}/h"
  echo ""
  echo "  总计 ${SP} 通过 / ${SF} 失败"
  rm -rf "${WORK}"
  [ "${SF}" -eq 0 ] || exit 1
  exit 0
fi

if [ "${MODE}" != scaffold ]; then
  preflight_installed_matches_repo "${REPO}" || exit 1
fi

mkdir -p "${WORK}"
mkgh "${WORK}/bin"
mk "${WORK}/happy"
mk "${WORK}/crash"
echo "  脚手架: ${WORK}"
if [ -z "$(CLAUDE_PROJECT_DIR="${WORK}/happy" CLAUDE_PLUGIN_ROOT="${PLUG}" bash "${PLUG}/hooks/phase-guard.sh" 2>/dev/null)" ]; then
  echo "  ❌ hook 静默 —— 脚手架没激活约定，评测无意义"; exit 1
fi
echo "  ✅ hook 已激活"

[ "${MODE}" = scaffold ] && { echo "  --scaffold-only：到此为止，未调用模型"; exit 0; }

export PATH="${WORK}/bin:${PATH}"
RUNFAIL=0
for arm in happy crash; do
  echo "  跑 ${arm} …"
  export GHLOG="${WORK}/${arm}.ghlog"; : > "${GHLOG}"
  export GHCNT="${WORK}/${arm}.cnt";   echo 100 > "${GHCNT}"
  export GHCREATES="${WORK}/${arm}.cre"; echo 0 > "${GHCREATES}"
  if [ "${arm}" = crash ]; then export FAILAT=3; else export FAILAT=0; fi
  run_headless "${WORK}/${arm}" "${WORK}/${arm}.out" \
    -p "${PROMPT}" --max-turns 20 --allowedTools Read Glob Grep Skill Bash Write Edit \
    || RUNFAIL=1
done
unset FAILAT
if [ "${RUNFAIL}" -ne 0 ]; then
  echo ""
  echo "  ⏭  评测没跑起来 —— **没有结论**，不要读成「操作一不成立」"
  exit 2
fi

echo ""
verdict "${WORK}/happy.ghlog" "${WORK}/happy" "${WORK}/crash.ghlog" "${WORK}/crash"
RC=$?
echo ""
case "${RC}" in
  0) echo "  ✅ 操作一（能力图落库）行为符合 0.7.19 之后的约定" ;;
  1) echo "  ❌ 操作一有不符合约定的行为，见上面的 ❌" ;;
  *) echo "  ⏭  没有结论" ;;
esac
exit "${RC}"
