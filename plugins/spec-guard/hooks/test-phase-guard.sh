#!/usr/bin/env bash
# phase-guard.sh 回归测试
# 用法: bash plugins/spec-guard/hooks/test-phase-guard.sh
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGDIR="$(cd "$HOOKDIR/.." && pwd)"
H="$HOOKDIR/phase-guard.sh"
[ -f "$H" ] || { echo "找不到 $H"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

base() {
  rm -rf "$TMP/r"; mkdir -p "$TMP/r"; cd "$TMP/r"
  git init -q 2>/dev/null
  echo "## Agent Skills 集成约定" > CLAUDE.md
  git add -A >/dev/null 2>&1
  git -c user.email=t@t -c user.name=t commit -qm init 2>/dev/null
}

phase() {
  CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null | python3 -c '
import sys, json, re
try:
    c = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
    p = re.search(r"当前阶段: \*\*(.+?)\*\*", c).group(1)
    n = len(re.findall("⚠", c))
    print(f"{p}|断链{n}")
except Exception:
    print("(无输出)")'
}

chk() {
  local got; got="$(phase)"
  if [ "$got" = "$2" ]; then
    printf '  ✅ %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  ❌ %s\n     得到 [%s]\n     期望 [%s]\n' "$1" "$got" "$2"; FAIL=$((FAIL+1))
  fi
}

echo "═══ phase-guard 回归测试 ═══"

base
chk "空仓库" "IDLE|断链0"

base; mkdir -p spec; touch spec/CAPABILITY-MAP.md
chk "只有能力图" "MAP_ONLY|断链1"

base; mkdir -p spec; touch spec/CAPABILITY-MAP.md spec/a.md
chk "spec无issue(无remote→本地)" "SPECED (本地模式)|断链1"

base; touch SPEC.md; mkdir -p spec; touch spec/a.md
chk "根目录SPEC(无remote→本地)" "SPECED (本地模式)|断链2"

base; mkdir -p spec tasks/x .agent; touch spec/a.md tasks/x/todo.md
echo '{"tracker":"github","activeModule":"x","modules":{"x":{"issue":9}}}' > .agent/state.json
chk "todo并存+无plan" "TRACKED|断链2"

base; mkdir -p spec tasks/x .agent; touch spec/a.md tasks/x/plan.md
echo '{"tracker":"github","activeModule":"x","modules":{"x":{"issue":9}}}' > .agent/state.json
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm p 2>/dev/null
git checkout -qb fix/9-abc 2>/dev/null
chk "干净待交付" "TASK_READY (gh 不可用，降级判定)|断链0"
echo x > f
chk "有改动" "BUILDING (gh 不可用，降级判定)|断链0"

base; mkdir -p spec tasks/x .agent; touch spec/a.md tasks/x/plan.md tasks/x/todo.md
echo '{"tracker":"none","activeModule":"x","modules":{"x":{}}}' > .agent/state.json
chk "本地模式齐全" "READY (本地模式)|断链0"

base; mkdir -p spec .agent; touch spec/a.md
echo '{"tracker":"none","activeModule":"x","modules":{"x":{}}}' > .agent/state.json
chk "本地模式缺plan" "SPECED (本地模式)|断链1"

base; mkdir -p spec .agent; touch spec/a.md
git remote add origin https://gitlab.com/a/b.git 2>/dev/null
echo '{"activeModule":"x","modules":{"x":{}}}' > .agent/state.json
chk "GitLab未声明tracker" "SPECED (非 GitHub tracker)|断链1"

rm -rf "$TMP/r2"; mkdir -p "$TMP/r2"; echo "# 普通项目" > "$TMP/r2/CLAUDE.md"
if [ -z "$(CLAUDE_PROJECT_DIR="$TMP/r2" bash "$H" 2>/dev/null)" ]; then
  printf '  ✅ 未启用仓库静默\n'; PASS=$((PASS+1))
else
  printf '  ❌ 未启用仓库不该有输出\n'; FAIL=$((FAIL+1))
fi

if [ -z "$(CLAUDE_PROJECT_DIR="$TMP/nope" bash "$H" 2>/dev/null)" ]; then
  printf '  ✅ 目录不存在不崩\n'; PASS=$((PASS+1))
else
  printf '  ❌ 目录不存在时不该有输出\n'; FAIL=$((FAIL+1))
fi

# ── setup-convention.sh 的回归 ──
echo ""
echo "═══ setup-convention 回归 ═══"
# 注意：此时可能已 cd 到临时目录，必须用脚本开头解析的绝对路径
SETUP="$HOOKDIR/setup-convention.sh"
export CLAUDE_PLUGIN_ROOT="$PLUGDIR"

rm -rf "$TMP/s"; mkdir -p "$TMP/s"; cd "$TMP/s"; git init -q 2>/dev/null
echo "# 原有内容" > CLAUDE.md
bash "$SETUP" local --dry-run >/dev/null 2>&1
if [ "$(ls -A | grep -vc '^.git$')" -eq 1 ]; then
  printf '  ✅ dry-run 零写入\n'; PASS=$((PASS+1))
else
  printf '  ❌ dry-run 不该写文件\n'; FAIL=$((FAIL+1))
fi

bash "$SETUP" local >/dev/null 2>&1
if head -1 CLAUDE.md | grep -q "原有内容"; then
  printf '  ✅ 原 CLAUDE.md 内容保留\n'; PASS=$((PASS+1))
else
  printf '  ❌ 覆盖了用户内容\n'; FAIL=$((FAIL+1))
fi

bash "$SETUP" local >/dev/null 2>&1
if [ "$(grep -c 'BEGIN:agent-skills-convention' CLAUDE.md)" -eq 1 ]; then
  printf '  ✅ 幂等（声明块不重复）\n'; PASS=$((PASS+1))
else
  printf '  ❌ 重复写入声明块\n'; FAIL=$((FAIL+1))
fi

echo ""
echo "  总计 $PASS 通过 / $FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
