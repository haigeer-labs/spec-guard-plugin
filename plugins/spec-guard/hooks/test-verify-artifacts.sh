#!/usr/bin/env bash
# verify-artifacts.sh 回归测试
# 用法: bash plugins/spec-guard/hooks/test-verify-artifacts.sh
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V="${HOOKDIR}/verify-artifacts.sh"
[ -f "${V}" ] || { echo "找不到 ${V}"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
PASS=0; FAIL=0

# 空的骨架：启用约定 + git 仓库，其余按用例自己铺
base() {
  rm -rf "${TMP}/r"; mkdir -p "${TMP}/r/spec" "${TMP}/r/.agent"; cd "${TMP}/r"
  git init -q 2>/dev/null
  echo "## Agent Skills 集成约定" > CLAUDE.md
}

map() {  # $@ = module ids
  { echo "# Capability Map"; echo ""
    echo "| Module id | Responsibility | Depends on |"; echo "|---|---|---|"
    for m in "$@"; do echo "| ${m} | x | — |"; done
    echo ""; echo "- [x] 已评审"; } > spec/CAPABILITY-MAP.md
}

# 跑一次，输出「通过数|警告数|失败数|退出码」
run() {
  local out rc
  out="$(CLAUDE_PROJECT_DIR="${TMP}/r" bash "${V}" 2>/dev/null)"; rc=$?
  printf '%s|%s' \
    "$(printf '%s' "${out}" | sed -n 's/.*═══ \([0-9]*\) 通过 \/ \([0-9]*\) 警告 \/ \([0-9]*\) 失败 ═══.*/\1,\2,\3/p' | tail -1)" \
    "${rc}"
}

chk() {  # $1=用例名 $2=期望 "通过,警告,失败|退出码"
  local got; got="$(run)"
  if [ "${got}" = "$2" ]; then
    printf '  ✅ %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  ❌ %s\n     得到 [%s]\n     期望 [%s]\n' "$1" "${got}" "$2"; FAIL=$((FAIL+1))
  fi
}

# 断言输出里出现/不出现某段文字
# 注意：不能写成 `bash "${V}" | grep -q`。grep -q 命中即关管道，还在输出的
# 脚本吃到 SIGPIPE(141)，pipefail 把它传出来，断言会永远判假。
has() {  # $1=用例名 $2=期望包含
  local out; out="$(CLAUDE_PROJECT_DIR="${TMP}/r" bash "${V}" 2>/dev/null)"
  case "${out}" in *"$2"*) true ;; *) false ;; esac
  if [ $? -eq 0 ]; then
    printf '  ✅ %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  ❌ %s（输出里没有 "%s"）\n' "$1" "$2"; FAIL=$((FAIL+1))
  fi
}

echo "═══ verify-artifacts 回归测试 ═══"

# ── 零误报：合规项目必须全绿 ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity; echo "## Task List" > tasks/identity/plan.md
echo '{"tracker":"none","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
chk "local 合规 → 零失败零警告" "5,0,0|0"

# ── B：文件名漂移（本脚本存在的首要理由）──
base; map identity; touch spec/user-identity.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "spec 文件名漂移被抓到" "能力图上没有的模块: user-identity"

# ── B：能力图上的模块还没写 spec，是提示不是失败 ──
base; map identity billing; touch spec/identity.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "未写的模块只提示不判失败" "还没写 spec 的模块: billing"
chk "  └ 且不计入失败" "4,0,0|0"

# ── A：模板占位符没填 ──
base; map example-a example-b; touch spec/example-a.md spec/example-b.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "模板占位符被警告" "还是模板占位符"

# ── A：module id 不是 kebab-case ──
base; map Identity_Module; touch spec/Identity_Module.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "非 kebab-case 被抓到" "不是 kebab-case"

# ── A：评审记录没勾完 ──
base; map identity; touch spec/identity.md
printf '\n- [ ] 模块边界确认\n' >> spec/CAPABILITY-MAP.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "评审未勾选被警告" "评审记录还有未勾选项"

# ── C：根目录 SPEC*.md ──
base; map identity; touch spec/identity.md SPEC.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "根目录 SPEC.md 被抓到" "根目录有 SPEC.md"

# ── C：tasks/ 缺 module 命名空间 ──
base; map identity; touch spec/identity.md
mkdir -p tasks; touch tasks/plan.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "tasks/ 缺命名空间被抓到" "缺 module 命名空间"

# ── C：todo.md 与 tracker 并存 ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity; touch tasks/identity/todo.md
echo '{"tracker":"github","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
has "todo.md 与 tracker 并存被抓到" "二者不能并存"

# ── D：github 模式下 plan.md 里有 checkbox ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity; printf '## Task List\n- [ ] 建表\n' > tasks/identity/plan.md
echo '{"tracker":"github","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
has "plan.md 里的 checkbox 被抓到" "应是 issue 编号索引"

# ── D：local 模式下 checkbox 是正常的，不该报 ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity; printf '## Task List\n- [ ] 建表\n' > tasks/identity/plan.md
echo '{"tracker":"none","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
chk "local 模式的 checkbox 不误报" "5,0,0|0"

# ── E：无 gh / 非 github 模式必须整段跳过，不能判失败 ──
base; map identity; touch spec/identity.md
echo '{"tracker":"gitlab","activeModule":""}' > .agent/state.json
has "非 GitHub tracker 跳过 GitHub 层" "不涉及 GitHub"

# ── 降级：state.json 缺失不崩，靠 remote 推断 ──
base; map identity; touch spec/identity.md
rm -f .agent/state.json
git remote add origin https://gitlab.com/a/b.git 2>/dev/null
has "无 state.json 时按 remote 推断" "tracker=other"

# ── 未启用约定：退出码 2，不做任何判断 ──
rm -rf "${TMP}/off"; mkdir -p "${TMP}/off"; echo "# 普通项目" > "${TMP}/off/CLAUDE.md"
CLAUDE_PROJECT_DIR="${TMP}/off" bash "${V}" >/dev/null 2>&1
if [ $? -eq 2 ]; then
  printf '  ✅ 未启用约定退出码 2\n'; PASS=$((PASS+1))
else
  printf '  ❌ 未启用约定应退出 2\n'; FAIL=$((FAIL+1))
fi

# ── 目录不存在不崩 ──
CLAUDE_PROJECT_DIR="${TMP}/nope" bash "${V}" >/dev/null 2>&1
if [ $? -eq 1 ]; then
  printf '  ✅ 目录不存在时干净报错\n'; PASS=$((PASS+1))
else
  printf '  ❌ 目录不存在时应退出 1\n'; FAIL=$((FAIL+1))
fi

echo ""
echo "  总计 ${PASS} 通过 / ${FAIL} 失败"
[ "${FAIL}" -eq 0 ] || exit 1
