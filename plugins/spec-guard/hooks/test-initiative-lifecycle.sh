#!/usr/bin/env bash
# initiative-lifecycle.sh 的 pause 安全性回归。
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIFECYCLE="$HOOKDIR/initiative-lifecycle.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }

PROJECT="$TMP/project"
mkdir -p "$PROJECT/spec" "$PROJECT/tasks/payment-api" "$PROJECT/.agent"
printf '# Capability Map: Payment\n\n## 目标\n\npay\n\n## 模块\n\n| Module id | Responsibility | Depends on |\n| --- | --- | --- |\n| payment-api | API | — |\n' > "$PROJECT/spec/CAPABILITY-MAP.md"
printf '# Spec\n' > "$PROJECT/spec/payment-api.md"
printf '# Plan\n' > "$PROJECT/tasks/payment-api/plan.md"
printf '{"activeModule":"payment-api","modules":{"payment-api":{"issue":101}}}\n' > "$PROJECT/.agent/state.json"

echo "═══ Initiative lifecycle regression ═══"
if [ -f "$LIFECYCLE" ] && "$LIFECYCLE" pause --project "$PROJECT" --initiative payment-v2 --dry-run >/dev/null 2>&1 \
  && [ -f "$PROJECT/spec/CAPABILITY-MAP.md" ] && [ -f "$PROJECT/spec/payment-api.md" ] \
  && [ -f "$PROJECT/tasks/payment-api/plan.md" ] && [ -f "$PROJECT/.agent/state.json" ]; then
  ok "正：pause --dry-run 只报告，不修改当前产物"
else
  bad "正：pause --dry-run 只报告，不修改当前产物"
fi

if [ -f "$LIFECYCLE" ] && ! "$LIFECYCLE" pause --project "$PROJECT" --initiative payment-v2 >/dev/null 2>&1 \
  && [ -f "$PROJECT/spec/CAPABILITY-MAP.md" ] && [ -f "$PROJECT/spec/payment-api.md" ] \
  && [ -f "$PROJECT/tasks/payment-api/plan.md" ] && [ -f "$PROJECT/.agent/state.json" ]; then
  ok "反：账本不存在时 pause 失败且不删除源文件"
else
  bad "反：账本不存在时 pause 失败且不删除源文件"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
