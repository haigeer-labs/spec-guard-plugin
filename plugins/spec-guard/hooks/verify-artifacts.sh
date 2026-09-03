#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# verify-artifacts.sh —— 产物落地校验（只读）
#
# phase-guard.sh 回答「现在在哪个阶段」，本脚本回答「已经落下的产物对不对」。
#
# 为什么需要它：整套约定从头到尾都是**提示词**——CLAUDE.md 里写「不要创建
# todo.md」、SKILL.md 里写「issue 正文不要粘贴 spec 全文」，全是对模型的建议。
# 软指令必须配硬检测，否则跑歪了没人知道。
#
# 为什么不并进 phase-guard：那个挂在 UserPromptSubmit 上，有 <1s 预算，
# 而这里的检查要读文件内容、打 gh。按需跑，不是每轮跑。
#
# 与 phase-guard 有三项重叠（根目录 SPEC*.md / todo.md 并存 / 分支归属），
# 是刻意的：一个「随时提醒」，一个「按需体检」，体检漏项比重复更糟。
# **重叠项的判定规则必须两边一致** —— 0.6.0 改了模块分支约定却只改了
# phase-guard，verify-artifacts 留在 task 分支时代，直到 0.7.11 才补上。
#
# 退出码: 0=无 FAIL（可能有 WARN）  1=有 FAIL  2=约定未启用
#
# 用法: CLAUDE_PROJECT_DIR=/path/to/project bash verify-artifacts.sh
# ─────────────────────────────────────────────────────────────
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${ROOT}" 2>/dev/null || { echo "❌ 进不去目录: ${ROOT}"; exit 1; }

# ── 归档识别 ──────────────────────────────────────────────
#   已完成的模块，其 todo.md 是**历史记录**，不是活的任务清单。
#   把它当成「与 tracker 并存」来报违规是误报 —— 而误报会让人关掉整个机制。
#   约定：文件**前 10 行**内出现 `已归档` 或 `ARCHIVED` 即视为归档。
#   放前 10 行是刻意的：只认头部声明，避免正文里偶然提到就被误判。
is_archived() {
  [ -f "$1" ] || return 1
  # herestring 而非管道：`head | grep -q` 里 grep 命中即关管道，还在写的 head
  # 吃到 SIGPIPE(141)，pipefail 把它传出来 —— 归档豁免失效，报出假违规。
  # 实测门槛是前 10 行约 256KB（真实 todo.md 到不了），但这是本仓明令禁止
  # 的写法，且同一条规则已经修过三次了。
  awk 'NR > 10 { exit } tolower($0) ~ /已归档|archived/ { found=1 } END { exit !found }' "$1"
}

# 列出所有**非归档**的 todo.md
live_todos() {
  find tasks -name "todo.md" 2>/dev/null | while IFS= read -r t; do
    is_archived "$t" || printf '%s\n' "$t"
  done
}

# ── 自身位置（用来找 hooks/spec-digest.py）────────────────
#   和 phase-guard 同样的解析方式：装出来时优先 PLUGIN_ROOT、再兼容
#   CLAUDE_PLUGIN_ROOT，
#   直接跑脚本时从 BASH_SOURCE 往上退一层到插件根。
SELF_DIR="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
if [ -z "${SELF_DIR}" ]; then
  SELF_DIR="${BASH_SOURCE[0]%/*}"; SELF_DIR="${SELF_DIR%/*}"
fi

P=0; W=0; F=0
ok()   { printf '  ✅ %s\n' "$1"; P=$((P+1)); }
warn() { printf '  ⚠️  %s\n' "$1"; W=$((W+1)); }
bad()  { printf '  ❌ %s\n' "$1"; F=$((F+1)); }
skip() { printf '  ⏭  %s\n' "$1"; }

# ── 约定未启用就别装懂 ──────────────────────────────────────
# 激活信号三种，满足其一即可：Claude 的说明块或旧版标题、Codex 的完整说明块，
# 或 .agent/state.json 存在
# （后者是零说明文件足迹模式，见 phase-guard.sh 同处注释）。
has_claude_block() {
  if grep -q "<!-- BEGIN:agent-skills-convention -->" CLAUDE.md 2>/dev/null; then
    return 0
  fi
  grep -q "Agent Skills 集成约定" CLAUDE.md 2>/dev/null
}

has_codex_block() {
  grep -q "<!-- BEGIN:spec-guard-codex-convention -->" AGENTS.md 2>/dev/null
}

HAS_CLAUDE=false
has_claude_block && HAS_CLAUDE=true
HAS_CODEX=false
has_codex_block && HAS_CODEX=true
HAS_BLOCK=false
if [ "$HAS_CLAUDE" = true ] || [ "$HAS_CODEX" = true ]; then
  HAS_BLOCK=true
fi
ACTIVE="$HAS_BLOCK"
[ -f .agent/state.json ] && ACTIVE=true
if [ "$ACTIVE" != true ]; then
  echo "本项目没有启用 spec-guard 约定（缺少项目说明块，且无 .agent/state.json）。"
  echo "先跑 /spec-guard:setup-convention。"
  exit 2
fi

STATE=".agent/state.json"

# 默认分支（模块 PR 的 base）。**不能只认 main/master 两个名字。**
# 默认分支叫 develop / trunk 的仓库上，本分支已落的 task 号一个都算不出来 ——
# 而 0.7.19 起「/next 跳过已做完的 task」这条筛选规则就靠这组号，
# 拿不到号 = 那个「刚做完的 task 被重新取一遍」的 bug 在这些仓库上原样存在。
#
# 顺序刻意先本地后远端、先 origin/HEAD 的名字后 main/master：
# 常见仓库（有本地 main）解析结果和 0.7.19 之前**逐字节相同**，只是把
# 覆盖面往外扩了一圈，不改已有行为。
# 全部落空就返回空 —— 调用方一律降级成「不排除任何东西」，
# 绝不反过来当成「都做完了」。
default_base() {
  local h n b
  h=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
  n="${h#origin/}"
  for b in "${n}" main master "$(git config --get init.defaultBranch 2>/dev/null || true)"; do
    [ -n "${b}" ] || continue
    git show-ref --verify --quiet "refs/heads/${b}" && { echo "${b}"; return; }
  done
  if [ -n "${h}" ] && git show-ref --verify --quiet "refs/remotes/${h}"; then echo "${h}"; return; fi
  for b in origin/main origin/master; do
    git show-ref --verify --quiet "refs/remotes/${b}" && { echo "${b}"; return; }
  done
  echo ""
}

jread() {  # $1=file  $2=python 表达式(d 为根对象)
  [ -f "$1" ] || return 0
  python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    v=$2
    print(v if v is not None else '')
except Exception:
    print('')
" "$1" 2>/dev/null
}

# 远端 host 解析与 phase-guard.sh 保持相同。
remote_host() {  # $1=remote url
  local h="$1"
  h="${h#*://}"; h="${h#*@}"; h="${h%%/*}"; h="${h%%:*}"
  printf '%s\n' "$h"
}

# 远端是不是 GitHub —— **只看 host 段**，与 phase-guard.sh 里那份逐字相同。
#   写 `*github.*` 会漏掉 SSH host 别名：`git@github-collab:o/r.git` 里
#   `github` 后面跟的是 `-` 不是 `.`。反过来松成 `*github*` 又会把
#   `gitlab.com/me/github-tools.git` 误判成 GitHub —— 那是仓库名不是宿主。
#   **两个 hook 共用的判据，改一处必须改另一处，两边都要加用例。**
is_github_remote() {  # $1=remote url
  local h
  h=$(remote_host "$1")
  case "$h" in *github*) return 0 ;; *) return 1 ;; esac
}

# GitLab.com 可从 host 无歧义判定；自建实例必须由 glab 的当前仓库查询确认，
# 不按 host 是否包含 gitlab 猜测。探测失败保持安全的本地回退。
is_gitlab_remote() {  # $1=remote url
  local h pid waited rc
  h=$(remote_host "$1")
  case "$h" in gitlab.com|*.gitlab.com) return 0 ;; esac
  command -v glab >/dev/null 2>&1 || return 1
  glab repo view >/dev/null 2>&1 &
  pid=$!; waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge 2 ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"; rc=$?
  return "$rc"
}

# ── tracker 判定（与 phase-guard 同一套顺序）────────────────
TRACKER=$(jread "${STATE}" "d.get('tracker')")
if [ -z "${TRACKER}" ]; then
  R=$(git remote get-url origin 2>/dev/null || echo "")
  if [ -z "${R}" ]; then TRACKER="none"
  elif is_github_remote "${R}"; then TRACKER="github"
  elif is_gitlab_remote "${R}"; then TRACKER="gitlab"
  else TRACKER="none"; fi
fi
MODULE=$(jread "${STATE}" "d.get('activeModule')")
EPIC=$(jread "${STATE}" "d.get('initiative',{}).get('issue')")

echo "═══ 产物落地校验 ═══"
echo "  tracker=${TRACKER}${MODULE:+  activeModule=${MODULE}}"
echo ""

# ── A. 能力图 ──────────────────────────────────────────────
echo "── A. 能力图 ──"
MAP="spec/CAPABILITY-MAP.md"
MAP_IDS=""
if [ ! -f "${MAP}" ]; then
  warn "${MAP} 不存在 —— 单模块项目可忽略；多模块的话 Phase 0 没落地"
else
  MAP_IDS=$(python3 -c '
import sys
ids = []
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.lstrip().startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 2:
        continue
    first = cells[0]
    if not first or first.lower() == "module id" or set(first) <= set("-: "):
        continue
    ids.append(first.strip(chr(96)))
print("\n".join(ids))
' "${MAP}")
  N=$(printf '%s' "${MAP_IDS}" | grep -c . || true)
  if [ "${N}" -eq 0 ]; then
    warn "${MAP} 里没解析出任何 module id —— 表格格式可能不对"
  elif [[ "${MAP_IDS}" == example-* ]]; then
    warn "${MAP} 还是模板占位符（example-a/example-b），没填真实模块"
  else
    ok "能力图解析出 ${N} 个 module id"
  fi

  # 评审记录没勾完
  if grep -q "^- \[ \]" "${MAP}" 2>/dev/null; then
    warn "能力图的评审记录还有未勾选项 —— Phase 0 是 gated 的，评审不能跳"
  fi

  # module id 必须 kebab-case
  BADID=$(printf '%s' "${MAP_IDS}" | grep -vE '^[a-z0-9]+(-[a-z0-9]+)*$' | grep . || true)
  [ -n "${BADID}" ] && bad "module id 不是 kebab-case: $(printf '%s' "${BADID}" | tr '\n' ' ')"
fi
echo ""

# ── A2. 能力图 ↔ 投影的指纹（纯本地，不打 gh）──────────────
#   和 phase-guard 那三条是同一份判据、同一个脚本。
#   **两个 hook 共用的判据必须在两边都有用例** —— 0.7.0 同时改了两边的激活
#   判据却只给 phase-guard 加了测试，verify-artifacts 漏了三个版本。
#   这里比 phase-guard 多说一件事：反方向（extra）在这儿只 warn 不 bad ——
#   手动跑的时候人在旁边，能自己判断是弃用还是手滑；每轮自动跑时不能问，
#   所以 phase-guard 那边整个不报。
echo "── A2. 能力图 ↔ 投影的指纹 ──"
DIGEST_PY="${SELF_DIR}/hooks/spec-digest.py"
if [ ! -f "${MAP}" ] || [ ! -f "${STATE}" ]; then
  skip "缺能力图或 state.json，跳过"
elif [ "${TRACKER}" != "github" ] && [ "${TRACKER}" != "gitlab" ]; then
  skip "tracker=${TRACKER}，当前 tracker 不写远端映射指纹"
elif [ ! -f "${DIGEST_PY}" ]; then
  skip "找不到 spec-digest.py，跳过（不代表通过）"
else
  DJ=$(python3 "${DIGEST_PY}" check "${MAP}" "${STATE}" 2>/dev/null || true)
  if [ -z "${DJ}" ]; then
    skip "指纹比对没跑起来，跳过（不代表通过）"
  else
    DOUT=$(printf '%s' "${DJ}" | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
if not d.get('ok'):
    print('SKIP|能力图没解析出真实模块（空表或 example-* 占位符）'); raise SystemExit
if d.get('syncedCount',0) < 1:
    print('SKIP|一个模块 issue 都还没落，Phase 0 尚未同步'); raise SystemExit
mis=d.get('missing') or []
if mis: print('BAD|能力图有 %d 个模块，其中 %d 个没落成 issue: %s' % (d['mapCount'], len(mis), ', '.join(mis)))
else:   print('OK|能力图的 %d 个模块都已落成 issue' % d['mapCount'])
g=d.get('goalStale')
if g is True:  print('BAD|能力图的「## 目标」段改过，Epic 正文摘要已过期 —— /spec-guard:sync-map 刷新')
elif g is None: print('SKIP|目标段指纹判不了（能力图无「## 目标」段，或 state.json 没存 goalDigest）')
else: print('OK|Epic 正文摘要与能力图目标段一致')
rs=d.get('rowsStale') or []
if rs: print('BAD|%s 的职责描述改过，对应 issue 正文摘要已过期 —— /spec-guard:sync-map 刷新' % ', '.join(rs))
ex=d.get('extra') or []
if ex: print('WARN|%s 在 state.json 里有 issue 号，但能力图里已经没有这一行 —— 弃用了就在 /spec-guard:sync-map 里确认，手滑删的就改回来' % ', '.join(ex))
" 2>/dev/null || true)
    if [ -z "${DOUT}" ]; then
      skip "指纹比对没给出结论，跳过（不代表通过）"
    else
      while IFS= read -r ln; do
        [ -n "${ln}" ] || continue
        case "${ln}" in
          OK\|*)   ok   "${ln#OK|}" ;;
          BAD\|*)  bad  "${ln#BAD|}" ;;
          WARN\|*) warn "${ln#WARN|}" ;;
          SKIP\|*) skip "${ln#SKIP|}" ;;
        esac
      done < <(printf '%s\n' "${DOUT}")
    fi
  fi
fi
echo ""
# ── B. spec 文件名 ↔ module id ─────────────────────────────
#   最阴险的一类漂移：能力图写 identity，模型建了 spec/user-identity.md。
#   phase-guard 只数 spec/*.md 的数量，从不比对，所以下游会静默错位。
echo "── B. spec 文件名 ↔ module id ──"
SPECS=$(ls -1 spec/*.md 2>/dev/null | sed 's|^spec/||;s|\.md$||' | grep -v "^CAPABILITY-MAP$" || true)
if [ -z "${MAP_IDS}" ]; then
  skip "无能力图，跳过比对"
elif [ -z "${SPECS}" ]; then
  warn "spec/ 下还没有模块 spec —— Phase 0 走完了但没递归"
else
  ORPHAN=$(comm -13 <(printf '%s\n' "${MAP_IDS}" | sort) <(printf '%s\n' "${SPECS}" | sort) | grep . || true)
  MISSING=$(comm -23 <(printf '%s\n' "${MAP_IDS}" | sort) <(printf '%s\n' "${SPECS}" | sort) | grep . || true)
  if [ -n "${ORPHAN}" ]; then
    bad "spec/ 里有能力图上没有的模块: $(printf '%s' "${ORPHAN}" | tr '\n' ' ')"
    printf '     上游原话：the map, not filename guessing, is the index of what exists\n'
  fi
  [ -n "${MISSING}" ] && printf '  ℹ  能力图上还没写 spec 的模块: %s（按 build order 逐个补）\n' \
    "$(printf '%s' "${MISSING}" | tr '\n' ' ')"
  [ -z "${ORPHAN}" ] && ok "spec 文件名与 module id 一致"
fi
echo ""

# ── C. 目录约定 ────────────────────────────────────────────
echo "── C. 目录约定 ──"
if ls -1 SPEC*.md >/dev/null 2>&1; then
  bad "根目录有 $(ls -1 SPEC*.md | tr '\n' ' ')—— /build 只认 spec/ 通配，挪进 spec/"
else
  ok "根目录无 SPEC*.md"
fi
ROOTFILES=""
for r in tasks/plan.md tasks/todo.md; do
  [ -f "$r" ] && ! is_archived "$r" && ROOTFILES="${ROOTFILES}${r} "
done
if [ -n "${ROOTFILES}" ]; then
  bad "tasks/ 根下有 ${ROOTFILES}—— 缺 module 命名空间，多模块时会互相覆盖"
elif [ -f "tasks/plan.md" ] || [ -f "tasks/todo.md" ]; then
  ok "tasks/ 根下只有已归档文件（不计违规）"
else
  ok "tasks/ 有 module 命名空间"
fi
if [ "${TRACKER}" != "none" ]; then
  T=$(live_todos | grep . || true)
  A=$(find tasks -name "todo.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ -n "${T}" ]; then
    bad "存在 $(printf '%s' "${T}" | tr '\n' ' ') 但已声明外部 tracker —— 二者不能并存，必然分叉"
    printf '     若它是已完成模块的历史记录：在前 10 行内写上「已归档」或 ARCHIVED 即可豁免\n'
  else
    ok "无活的 todo.md 与 tracker 并存$( [ "${A}" -gt 0 ] && echo "（${A} 份已归档，不计）" )"
  fi
fi
echo ""

# ── D. plan.md 内容 ────────────────────────────────────────
echo "── D. plan.md ──"
if [ -z "${MODULE}" ]; then
  skip "state.json 没有 activeModule"
elif [ ! -f "tasks/${MODULE}/plan.md" ]; then
  warn "tasks/${MODULE}/plan.md 不存在 —— /plan 还没跑"
else
  PLAN="tasks/${MODULE}/plan.md"
  if [ "${TRACKER}" = "github" ] || [ "${TRACKER}" = "gitlab" ]; then
    if grep -qE '^\s*- \[[ x]\]' "${PLAN}"; then
      bad "${PLAN} 里有 checkbox —— tracker 模式下 Task List 应是 issue 编号索引，不是 checklist"
    else
      ok "${PLAN} 的 Task List 不是 checklist"
    fi
    grep -qi "tracked in" "${PLAN}" \
      && ok "${PLAN} 注明了 tracker 位置" \
      || warn "${PLAN} 没写「Tasks tracked in ...」—— 跨会话续接会找不到任务在哪"
  else
    ok "${PLAN} 存在"
  fi
fi
echo ""

# ── E. GitHub 层（探测失败就整段跳过，绝不误报）────────────
echo "── E. GitHub 层 ──"
if [ "${TRACKER}" != "github" ]; then
  skip "tracker=${TRACKER}，不涉及 GitHub"
elif ! command -v gh >/dev/null 2>&1; then
  skip "gh 未安装，跳过（不代表通过）"
elif ! gh auth status >/dev/null 2>&1; then
  skip "gh 未认证，跳过（不代表通过）"
else
  # 重复的 Epic —— 0.7.13 那条「操作一中途失败后重跑」的后果，至今没人查
  #
  #   操作一在外部系统上做不可逆写入，而它中途会失败（限流 / `--type` 被拒 /
  #   用户按停）。0.7.13 之后 state.json 是**增量**写回的，重跑本该可续；
  #   但那条只是 skill 里的一句话，0.7.13 之前建起来的项目、以及模型没照做的
  #   那次，仍然会落到「GitHub 上已经有一个 Epic / state.json 里没有它」——
  #   重跑的前置判据读的正是 `initiative.issue`，它是空的，于是再建一套。
  #
  #   已有的每一项都够不到那个多出来的 Epic：sub-issue 数、正文体量、指纹，
  #   问的全是 state.json 记着的那一个。**没被记下的那个，没有任何东西看得见。**
  #
  #   判据刻意收得很紧（A1：假断链比不报断链危害大得多）：
  #     · 只看 open —— 上一个 initiative 做完关掉的 Epic 不该算进来
  #     · 比的是「与记录在案的那个 Epic **标题逐字相同**」，不是「像 Epic 的都算」。
  #       重跑用的是同一份能力图，标题必然相同；而两个**不同名**的 initiative
  #       同时开着是正常的（0.5.1「刻意空闲」的邻居）
  #     · 记录在案的 Epic 不在 open 列表里（已关闭 / 超出 201 条）→ skip，不猜
  #     · state.json 没有 initiative.issue、而 GitHub 上已有 `Initiative:` 开头的
  #       open issue → 只 warn：这是「重跑会再建一套」的前夜，但那个 issue
  #       也可能是人手建的、跟本插件无关
  ELIST=$(gh issue list --state open --limit 201 --json number,title 2>/dev/null || echo "")
  if [ -z "${ELIST}" ]; then
    skip "读不到 open issue 列表（网络或权限），跳过重复 Epic 比对（不代表通过）"
  else
    EOUT=$(printf '%s' "${ELIST}" | python3 -c "
import json,sys
epic=sys.argv[1]
try: items=json.load(sys.stdin)
except Exception: raise SystemExit
if not isinstance(items,list): raise SystemExit
def norm(t): return ' '.join((t or '').split())
if epic:
    rec=[i for i in items if str(i.get('number'))==epic]
    if not rec:
        print('SKIP|state.json 记的 Epic #%s 不在 open issue 列表里（已关闭，或超出前 201 条），跳过重复 Epic 比对（不代表通过）' % epic); raise SystemExit
    t=rec[0].get('title') or ''
    dups=[str(i.get('number')) for i in items if str(i.get('number'))!=epic and (i.get('title') or '')==t]
    if dups:
        print('BAD|除了 state.json 记的 Epic #%s，还有同名的 open issue: %s —— 操作一中途失败后重跑的残留。先人工分辨留哪一套，依赖关系和 sub-issue 层级都要重连' % (epic, ', '.join('#'+d for d in dups)))
    elif len(items)>=201:
        print('SKIP|open issue 列表返回至少 201 条，可能已截断；窗口内未找到与 Epic #%s 同名的其他 open issue，不代表通过，跳过重复 Epic 比对' % epic)
    else:
        print('OK|没有与 Epic #%s 同名的其他 open issue' % epic)
else:
    cands=[str(i.get('number')) for i in items if norm(i.get('title')).lower().startswith('initiative:')]
    if cands:
        print('WARN|state.json 没有 initiative.issue，但 GitHub 上已有标题像 Epic 的 open issue %s —— 若它是上次 /sync-map 建到一半留下的，重跑会再建一套；把号补进 state.json 就能续上' % ', '.join('#'+c for c in cands))
    else:
        print('OK|GitHub 上没有孤儿 Epic')
" "${EPIC}" 2>/dev/null || true)
    if [ -z "${EOUT}" ]; then
      skip "重复 Epic 比对没给出结论，跳过（不代表通过）"
    else
      case "${EOUT}" in
        OK\|*)   ok   "${EOUT#OK|}" ;;
        BAD\|*)  bad  "${EOUT#BAD|}" ;;
        WARN\|*) warn "${EOUT#WARN|}" ;;
        SKIP\|*) skip "${EOUT#SKIP|}" ;;
      esac
    fi
  fi

  # Epic 的 sub-issue 数 == 能力图模块数
  if [ -n "${EPIC}" ] && [ -n "${MAP_IDS}" ]; then
    # REST sub_issues —— `gh issue list` 没有 --parent flag
    SUBN=$(gh api "repos/{owner}/{repo}/issues/${EPIC}/sub_issues" 2>/dev/null \
           | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "")
    MAPN=$(printf '%s' "${MAP_IDS}" | grep -c . || true)
    if [ -z "${SUBN}" ]; then
      skip "读不到 Epic #${EPIC} 的 sub-issue（网络或权限），跳过"
    elif [ "${SUBN}" -ne "${MAPN}" ]; then
      bad "Epic #${EPIC} 有 ${SUBN} 个 sub-issue，能力图有 ${MAPN} 个模块 —— 对不上"
    else
      ok "Epic #${EPIC} 的模块 issue 数与能力图一致（${MAPN}）"
    fi
  else
    skip "state.json 没有 initiative.issue，跳过 Epic 比对"
  fi

  # Epic 正文是否粘贴了能力图全文
  #   这一处到 0.7.19 才有。此前只体检模块 issue 的正文，而**唯一一处流程
  #   明确指示粘贴全文的地方恰恰是 Epic**（操作一步骤 2 原来写的是
  #   `--body-file spec/CAPABILITY-MAP.md`）—— 检查器盖不到发布方自己写的
  #   那条错。规则写在 skill 里，判据落在这里，两边差了一个 issue 的距离。
  #   比的是 Epic 正文 vs 能力图本身，同一份文档，粘贴全文时比值 ≈ 1，
  #   摘要通常远低于 1/3，2/3 这个阈值和模块那处是可比的。
  if [ -n "${EPIC}" ] && [ -f "${MAP}" ]; then
    EBODY=$(gh issue view "${EPIC}" --json body -q '.body' 2>/dev/null || echo "")
    ML=$(wc -c < "${MAP}" | tr -d ' ')
    if [ -z "${EBODY}" ]; then
      skip "读不到 Epic #${EPIC} 的正文（网络/权限，或正文本就是空的），跳过体量比对"
    else
      EL=$(printf '%s' "${EBODY}" | wc -c | tr -d ' ')
      if [ "${ML}" -gt 0 ] && [ "${EL}" -gt $((ML * 2 / 3)) ]; then
        warn "Epic #${EPIC} 正文 ${EL} 字节 vs 能力图 ${ML} 字节 —— 疑似灌了能力图全文，能力图会改，复制必然分叉"
      else
        ok "Epic #${EPIC} 正文是摘要而非能力图全文"
      fi
    fi
  fi

  # 模块 issue 正文是否粘贴了 spec 全文
  MI=$(jread "${STATE}" "d.get('modules',{}).get('${MODULE}',{}).get('issue')")
  if [ -n "${MI}" ] && [ -f "spec/${MODULE}.md" ]; then
    # 读不到正文（被删 / 权限 / 网络）时**必须 skip，不能报 ok**。
    # 原先 gh 失败 → BL=0 → 落进 else → 打出「✅ 正文是摘要而非 spec 全文」,
    # 把「没查成」算成「查过了没问题」。本段段头写的是「探测失败就整段跳过,
    # 绝不误报」,同段另外三处（Epic / 父 issue / PR 正文）都老实 skip,
    # 只有这一处发没挣来的绿灯 —— 而这个脚本存在的意义就是不发这种绿灯。
    IBODY=$(gh issue view "${MI}" --json body -q '.body' 2>/dev/null || echo "")
    SL=$(wc -c < "spec/${MODULE}.md" | tr -d ' ')
    if [ -z "${IBODY}" ]; then
      skip "读不到 issue #${MI} 的正文（网络/权限，或正文本就是空的），跳过体量比对"
    else
      BL=$(printf '%s' "${IBODY}" | wc -c | tr -d ' ')
      if [ "${SL}" -gt 0 ] && [ "${BL}" -gt $((SL * 2 / 3)) ]; then
        warn "issue #${MI} 正文 ${BL} 字节 vs spec ${SL} 字节 —— 疑似粘贴了 spec 全文，spec 会改，复制必然分叉"
      else
        ok "issue #${MI} 正文是摘要而非 spec 全文"
      fi
    fi
  fi

  # 模块的 sub-issue 数 ↔ plan.md 的 Task List 条目数
  #
  # 补这一项是因为「任务落库」此前**完全没有产物校验**：SKILL 的 Verification
  # 里写着「sub_issues 条目数 == plan.md 索引条数」，但没有任何东西真去比。
  # 它一次盖住两种失败：
  #   · 一条 sub-issue 都没有 = 任务从没落库（phase-guard 那边判 PLANNED (任务未落库)）
  #   · 两边对不上 = 落库中途失败后重跑的残留，或 plan.md 没回写全
  if [ -n "${MI}" ] && [ -f "tasks/${MODULE}/plan.md" ]; then
    PN=$(grep -coE '^[[:space:]]*[-*][[:space:]]+#[0-9]+' "tasks/${MODULE}/plan.md" || true)
    [ -z "${PN}" ] && PN=0
    SUBJ=$(gh api "repos/{owner}/{repo}/issues/${MI}/sub_issues" 2>/dev/null \
           | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "")
    if [ -z "${SUBJ}" ]; then
      skip "读不到模块 issue #${MI} 的 sub-issue（网络或权限），跳过任务落库比对"
    elif [ "${PN}" -eq 0 ] && [ "${SUBJ}" -eq 0 ]; then
      warn "tasks/${MODULE}/plan.md 没有 issue 编号索引，#${MI} 下也没有 sub-issue —— 任务还没落库"
    elif [ "${PN}" -eq 0 ]; then
      warn "#${MI} 下有 ${SUBJ} 个 sub-issue，但 plan.md 的 Task List 一个编号都没写 —— 跨会话续接会找不到任务在哪"
    elif [ "${SUBJ}" -eq 0 ]; then
      bad "plan.md 索引了 ${PN} 个 task，但 #${MI} 下一个 sub-issue 都没有 —— 任务从没落库"
    elif [ "${PN}" -ne "${SUBJ}" ]; then
      warn "plan.md 索引 ${PN} 个 task，#${MI} 下有 ${SUBJ} 个 sub-issue —— 对不上（落库中途失败重跑的残留？或 plan.md 没回写全）"
    else
      ok "任务落库数与 plan.md 索引一致（${PN}）"
    fi
  fi

  # 当前分支是模块分支还是 task 分支
  #
  # 0.6.0 把 PR 粒度从 task 提到 module，phase-guard 同步改了，**这里没有** ——
  # 当时误判「verify-artifacts 没有分支逻辑」（grep 找的是 BRANCH，而这里叫 BR）。
  # 后果是模块名自带数字时（`feat/oauth2`）那个 `2` 被当成 issue 号，
  # 报出「PR 正文没有 Closes #2」这种**假失败** —— 而 PR 正文里写的是
  # 正确的 `Closes #<module-issue>`。
  #
  # 判定规则与 phase-guard 一致：**末段整段相等**，不是子串包含。
  BR=$(git branch --show-current 2>/dev/null || echo "")
  ON_MOD=false
  if [ -n "${BR}" ] && [ -n "${MODULE}" ]; then
    case "${BR}" in "${MODULE}"|*/"${MODULE}") ON_MOD=true ;; esac
  fi
  BRI=""
  [ "${ON_MOD}" = false ] && BRI=$(printf '%s' "${BR}" | grep -oE '[0-9]+' | head -1 || true)

  if [ "${ON_MOD}" = true ]; then
    # 模块分支：PR 正文该关的是**模块 issue**；task issue 靠 commit message 关
    PRB=$(gh pr view --json body -q '.body' 2>/dev/null || echo "")
    if [ -z "${PRB}" ]; then
      skip "模块分支 ${BR} 还没有 PR（模块跑完再开）"
    elif [[ "$(printf '%s' "${PRB}" | tr '[:upper:]' '[:lower:]')" =~ closes[[:space:]]+#${MI} ]]; then
      ok "模块 PR 正文含 Closes #${MI}"
    else
      bad "模块 PR 正文没有 Closes #${MI} —— 模块 issue 不会自动关闭"
    fi
    BASE=$(default_base)
    if [ -z "${BASE}" ] || [ "${BASE}" = "${BR}" ]; then
      # 原先这里是**静默**跳过：BASE 取不到时整段消失，连一行 ⏭ 都没有。
      # 同一个脚本对其余每一处探测失败都老实 skip —— 本段段头写的就是
      # 「探测失败就整段跳过」，跳过也要说出来，否则「没查」和「查过没问题」
      # 在输出里长得一模一样。
      skip "认不出默认分支（试过 origin/HEAD、main、master、init.defaultBranch），跳过 closing keyword 比对"
    else
      NC=$(git log -n 200 --format=%B "${BASE}..HEAD" 2>/dev/null \
        | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#[0-9]+' \
        | grep -oE '[0-9]+' | sort -u | grep -c . || true)
      [ -z "${NC}" ] && NC=0
      if [ "${NC}" -gt 0 ]; then
        ok "本分支 ${NC} 条 commit 带 closing keyword（task issue 靠它们关）"
      else
        warn "本分支没有一条 commit 带 Closes #<task-issue> —— 合并后 task issue 不会关"
      fi
    fi
  elif [ -n "${BRI}" ]; then
    # task 分支（老约定，仍然支持）
    PRB=$(gh pr view --json body -q '.body' 2>/dev/null || echo "")
    if [ -z "${PRB}" ]; then
      skip "分支 ${BR} 还没有 PR"
    elif [[ "$(printf '%s' "${PRB}" | tr '[:upper:]' '[:lower:]')" =~ closes[[:space:]]+#${BRI} ]]; then
      ok "PR 正文含 Closes #${BRI}"
    else
      bad "PR 正文没有 Closes #${BRI} —— issue 不会自动关闭，Project 看板不流转"
    fi
  fi

  # activeModule 与当前分支是否对得上
  if [ -n "${BRI}" ] && [ -n "${MI}" ]; then
    PAR=$(gh issue view "${BRI}" --json parent -q '.parent.number' 2>/dev/null || echo "")
    if [ -z "${PAR}" ]; then
      skip "读不到 #${BRI} 的父 issue，跳过归属校验"
    elif [ "${PAR}" != "${MI}" ]; then
      bad "分支在做 #${BRI}（父 #${PAR}），但 activeModule=${MODULE} 的 issue 是 #${MI} —— 对不上"
    else
      ok "当前分支的 task 属于 activeModule"
    fi
  fi
fi

echo ""
echo "── F. GitLab 层 ──"
if [ "${TRACKER}" != "gitlab" ]; then
  skip "tracker=${TRACKER}，不涉及 GitLab"
elif ! command -v glab >/dev/null 2>&1; then
  skip "glab 未安装，跳过（不代表通过）"
elif ! glab auth status >/dev/null 2>&1; then
  skip "glab 未认证或 API 不可用，跳过（不代表通过）"
else
  GL_PROJECT=$(glab repo view --output json 2>/dev/null | python3 -c \
    'import json,sys; print(json.load(sys.stdin).get("path_with_namespace", ""))' 2>/dev/null || echo "")
  GL_PROJECT_ID=$(glab api "projects/${GL_PROJECT//\//%2F}" 2>/dev/null | python3 -c \
    'import json,sys; print(json.load(sys.stdin).get("id", ""))' 2>/dev/null || echo "")
  if [ -z "${GL_PROJECT}" ] || [ -z "${GL_PROJECT_ID}" ]; then
    skip "读不到当前 GitLab 项目，跳过 Issue 映射校验（不代表通过）"
  else
    GL_ROWS=$(python3 -c '
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: raise SystemExit
initiative=d.get("initiative",{}).get("issue")
if isinstance(initiative, int) or (isinstance(initiative,str) and initiative.isdigit()): print("initiative\t%s" % initiative)
for module, item in (d.get("modules") or {}).items():
    issue=(item or {}).get("issue") if isinstance(item,dict) else None
    if isinstance(issue, int) or (isinstance(issue,str) and issue.isdigit()): print("module:%s\t%s" % (module, issue))
' "${STATE}" 2>/dev/null || true)
    if [ -z "${GL_ROWS}" ]; then
      skip "state.json 没有 GitLab initiative 或模块 Issue，跳过远端映射校验"
    else
      GL_COUNT=0; GL_UNREADABLE=false
      while IFS="$(printf '\t')" read -r GL_KIND GL_IID; do
        [ -n "${GL_IID}" ] || continue
        GL_JSON=$(glab api "projects/${GL_PROJECT_ID}/issues/${GL_IID}" 2>/dev/null || echo "")
        GL_STATE=$(printf '%s' "${GL_JSON}" | python3 -c \
          'import json,sys; print(json.load(sys.stdin).get("state", ""))' 2>/dev/null || echo "")
        if [ -z "${GL_STATE}" ]; then
          skip "读不到 GitLab ${GL_KIND} Issue #${GL_IID}，跳过剩余映射校验（不代表通过）"
          GL_UNREADABLE=true
          break
        fi
        GL_COUNT=$((GL_COUNT + 1))
        if [ "${GL_KIND}" = "module:${MODULE}" ] && [ "${GL_STATE}" != "opened" ]; then
          warn "activeModule=${MODULE} 的 GitLab Issue #${GL_IID} 是 ${GL_STATE}，先刷新 state 再继续"
        else
          ok "GitLab ${GL_KIND} Issue #${GL_IID} 可读取（${GL_STATE}）"
        fi
      done <<EOF
${GL_ROWS}
EOF
      [ "${GL_UNREADABLE}" = false ] && ok "GitLab state 记录的 ${GL_COUNT} 条 Issue 都可读取"
    fi
  fi
fi

echo ""
echo "═══ ${P} 通过 / ${W} 警告 / ${F} 失败 ═══"
if [ "${F}" -gt 0 ]; then
  echo ""
  echo "失败项要先向用户说明再处理，不要自作主张补齐 —— 有些是用户故意的。"
  exit 1
fi
exit 0
