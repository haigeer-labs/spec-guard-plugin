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
has_glob() { compgen -G "$1" >/dev/null; }

PROJECT="$TMP/project"
mkdir -p "$PROJECT/spec" "$PROJECT/tasks/payment-api" "$PROJECT/tasks/ledger" "$PROJECT/.agent"
printf '# Capability Map: Payment\n\n## 目标\n\npay\n\n## 模块\n\n| Module id | Responsibility | Depends on |\n| --- | --- | --- |\n| payment-api | API | — |\n| ledger | Ledger entries | payment-api |\n' > "$PROJECT/spec/CAPABILITY-MAP.md"
printf '# Spec\n' > "$PROJECT/spec/payment-api.md"
printf '# Ledger\n' > "$PROJECT/spec/ledger.md"
printf '# Plan\n' > "$PROJECT/tasks/payment-api/plan.md"
printf '# Ledger plan\n' > "$PROJECT/tasks/ledger/plan.md"
printf '{"activeModule":"payment-api","modules":{"payment-api":{"issue":101},"ledger":{"issue":102}}}\n' > "$PROJECT/.agent/state.json"

echo "═══ Initiative lifecycle regression ═══"
if [ -f "$LIFECYCLE" ] && "$LIFECYCLE" pause --project "$PROJECT" --initiative payment-v2 --dry-run >/dev/null 2>&1 \
  && [ -f "$PROJECT/spec/CAPABILITY-MAP.md" ] && [ -f "$PROJECT/spec/payment-api.md" ] \
  && [ -f "$PROJECT/tasks/payment-api/plan.md" ] && [ -f "$PROJECT/.agent/state.json" ]; then
  ok "正：pause --dry-run 只报告，不修改当前产物"
else
  bad "正：pause --dry-run 只报告，不修改当前产物"
fi

if [ -f "$LIFECYCLE" ] && "$LIFECYCLE" pause --project "$PROJECT" --initiative payment-v2 >/dev/null 2>&1 \
  && [ ! -f "$PROJECT/spec/CAPABILITY-MAP.md" ] && [ ! -f "$PROJECT/.agent/state.json" ] \
  && [ ! -f "$PROJECT/spec/payment-api.md" ] && [ ! -f "$PROJECT/spec/ledger.md" ] \
  && [ ! -f "$PROJECT/tasks/payment-api/plan.md" ] && [ ! -f "$PROJECT/tasks/ledger/plan.md" ] \
  && [ -f "$PROJECT/spec/CAPABILITY-HISTORY.json" ] \
  && [ "$(python3 "$HOOKDIR/capability-history.py" status "$PROJECT/spec/CAPABILITY-HISTORY.json" payment-v2)" = paused ] \
  && has_glob "$PROJECT/spec/history/payment-v2/*/CAPABILITY-MAP.md" \
  && has_glob "$PROJECT/spec/history/payment-v2/*/payment-api.md" \
  && has_glob "$PROJECT/spec/history/payment-v2/*/ledger.md" \
  && has_glob "$PROJECT/tasks/history/payment-v2/*/payment-api/plan.md" \
  && has_glob "$PROJECT/tasks/history/payment-v2/*/ledger/plan.md" \
  && has_glob "$PROJECT/.agent/history/payment-v2/*/state.json" \
  && python3 - "$PROJECT/spec/CAPABILITY-HISTORY.json" <<'PY'
import json
import sys

ledger = json.load(open(sys.argv[1], encoding="utf-8"))
modules = ledger["initiatives"][0]["events"][-1]["checkpoint"]["modules"]
assert [(module["id"], module["responsibility"], module["dependsOn"], module["status"])
        for module in modules] == [
    ("payment-api", "API", [], "unknown"),
    ("ledger", "Ledger entries", ["payment-api"], "unknown"),
]
PY
then
  ok "正：账本不存在时 pause 自动建账并归档当前工作区"
else
  bad "正：账本不存在时 pause 自动建账并归档当前工作区"
fi

HISTORY="$HOOKDIR/capability-history.py"
CREATED="$TMP/created.json"
printf '%s\n' '{"id":"payment-v2","title":"Payment v2","events":[{"type":"created","at":"2026-09-02T09:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/payment-v2/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}}]}' > "$CREATED"

TERMINAL_PROJECT="$TMP/terminal-project"
mkdir -p "$TERMINAL_PROJECT/spec" "$TERMINAL_PROJECT/.agent"
: > "$TERMINAL_PROJECT/spec/CAPABILITY-MAP.md"
printf '{}' > "$TERMINAL_PROJECT/.agent/state.json"
if "$LIFECYCLE" complete --project "$TERMINAL_PROJECT" --initiative payment-v2 >/dev/null 2>&1 \
  && [ ! -f "$TERMINAL_PROJECT/spec/CAPABILITY-MAP.md" ] \
  && [ "$(python3 "$HISTORY" status "$TERMINAL_PROJECT/spec/CAPABILITY-HISTORY.json" payment-v2)" = completed ] \
  && has_glob "$TERMINAL_PROJECT/spec/history/payment-v2/*/CAPABILITY-MAP.md"; then
  ok "正：账本不存在时 complete 自动建账、写入终态 checkpoint 后清理当前工作区"
else
  bad "正：账本不存在时 complete 自动建账、写入终态 checkpoint 后清理当前工作区"
fi

EXISTING_LEDGER_PROJECT="$TMP/existing-ledger-project"
mkdir -p "$EXISTING_LEDGER_PROJECT/spec" "$EXISTING_LEDGER_PROJECT/.agent"
printf '# Current map\n' > "$EXISTING_LEDGER_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"activeModule":null,"modules":{}}\n' > "$EXISTING_LEDGER_PROJECT/.agent/state.json"
EXISTING_CREATED="$TMP/existing-created.json"
printf '%s\n' '{"id":"older-initiative","title":"Older initiative","events":[{"type":"created","at":"2026-09-02T09:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/older-initiative/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}},{"type":"completed","at":"2026-09-02T10:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/older-initiative/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}}]}' > "$EXISTING_CREATED"
python3 "$HISTORY" create "$EXISTING_LEDGER_PROJECT/spec/CAPABILITY-HISTORY.json" "$EXISTING_CREATED" >/dev/null 2>&1
if "$LIFECYCLE" complete --project "$EXISTING_LEDGER_PROJECT" --initiative new-initiative >/dev/null 2>&1 \
  && [ ! -f "$EXISTING_LEDGER_PROJECT/spec/CAPABILITY-MAP.md" ] \
  && [ "$(python3 "$HISTORY" status "$EXISTING_LEDGER_PROJECT/spec/CAPABILITY-HISTORY.json" older-initiative)" = completed ] \
  && [ "$(python3 "$HISTORY" status "$EXISTING_LEDGER_PROJECT/spec/CAPABILITY-HISTORY.json" new-initiative)" = completed ] \
  && has_glob "$EXISTING_LEDGER_PROJECT/spec/history/new-initiative/*/CAPABILITY-MAP.md"; then
  ok "正：已有其他 initiative 的账本可登记并完成新的 initiative"
else
  bad "正：已有其他 initiative 的账本可登记并完成新的 initiative"
fi

RESUME_PROJECT="$TMP/resume-project"
RESUME_CHECKPOINT="20260904T090000Z-0002"
mkdir -p "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT" \
  "$RESUME_PROJECT/tasks/history/payment-v2/$RESUME_CHECKPOINT/payment-api" \
  "$RESUME_PROJECT/.agent/history/payment-v2/$RESUME_CHECKPOINT"
printf '# Restored map\n' > "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT/CAPABILITY-MAP.md"
printf '# Restored spec\n' > "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT/payment-api.md"
printf '# Restored plan\n' > "$RESUME_PROJECT/tasks/history/payment-v2/$RESUME_CHECKPOINT/payment-api/plan.md"
printf '{"activeModule":"payment-api"}\n' > "$RESUME_PROJECT/.agent/history/payment-v2/$RESUME_CHECKPOINT/state.json"
MAP_SHA="$(shasum -a 256 "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT/CAPABILITY-MAP.md" | awk '{print $1}')"
SPEC_SHA="$(shasum -a 256 "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT/payment-api.md" | awk '{print $1}')"
PLAN_SHA="$(shasum -a 256 "$RESUME_PROJECT/tasks/history/payment-v2/$RESUME_CHECKPOINT/payment-api/plan.md" | awk '{print $1}')"
STATE_SHA="$(shasum -a 256 "$RESUME_PROJECT/.agent/history/payment-v2/$RESUME_CHECKPOINT/state.json" | awk '{print $1}')"
RESUME_CREATED="$TMP/resume-created.json"
RESUME_PAUSED="$TMP/resume-paused.json"
printf '%s\n' '{"id":"payment-v2","title":"Payment v2","events":[{"type":"created","at":"2026-09-02T09:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/payment-v2/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}}]}' > "$RESUME_CREATED"
printf '%s\n' "{\"type\":\"paused\",\"at\":\"2026-09-04T09:00:00Z\",\"checkpoint\":{\"id\":\"$RESUME_CHECKPOINT\",\"map\":{\"path\":\"spec/history/payment-v2/$RESUME_CHECKPOINT/CAPABILITY-MAP.md\",\"sha256\":\"$MAP_SHA\"},\"state\":{\"path\":\".agent/history/payment-v2/$RESUME_CHECKPOINT/state.json\",\"sha256\":\"$STATE_SHA\"},\"modules\":[{\"id\":\"payment-api\",\"responsibility\":\"Payment API\",\"dependsOn\":[],\"status\":\"in-progress\",\"issue\":101,\"spec\":{\"path\":\"spec/history/payment-v2/$RESUME_CHECKPOINT/payment-api.md\",\"sha256\":\"$SPEC_SHA\"},\"plan\":{\"path\":\"tasks/history/payment-v2/$RESUME_CHECKPOINT/payment-api/plan.md\",\"sha256\":\"$PLAN_SHA\"}}]}}" > "$RESUME_PAUSED"
python3 "$HISTORY" create "$RESUME_PROJECT/spec/CAPABILITY-HISTORY.json" "$RESUME_CREATED" >/dev/null 2>&1 || true
python3 "$HISTORY" append "$RESUME_PROJECT/spec/CAPABILITY-HISTORY.json" payment-v2 "$RESUME_PAUSED" >/dev/null 2>&1 || true
if "$LIFECYCLE" resume --project "$RESUME_PROJECT" --initiative payment-v2 >/dev/null 2>&1 \
  && [ "$(cat "$RESUME_PROJECT/spec/CAPABILITY-MAP.md")" = '# Restored map' ] \
  && [ "$(cat "$RESUME_PROJECT/spec/payment-api.md")" = '# Restored spec' ] \
  && [ "$(cat "$RESUME_PROJECT/tasks/payment-api/plan.md")" = '# Restored plan' ] \
  && [ "$(cat "$RESUME_PROJECT/.agent/state.json")" = '{"activeModule":"payment-api"}' ] \
  && [ "$(python3 "$HISTORY" status "$RESUME_PROJECT/spec/CAPABILITY-HISTORY.json" payment-v2)" = resumed ]; then
  ok "正：resume 恢复最后 paused checkpoint 的全部当前产物"
else
  bad "正：resume 恢复最后 paused checkpoint 的全部当前产物"
fi

printf 'tampered map\n' > "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT/CAPABILITY-MAP.md"
printf 'keep current\n' > "$RESUME_PROJECT/spec/CAPABILITY-MAP.md"
if ! "$LIFECYCLE" resume --project "$RESUME_PROJECT" --initiative payment-v2 >/dev/null 2>&1 \
  && [ "$(cat "$RESUME_PROJECT/spec/CAPABILITY-MAP.md")" = 'keep current' ]; then
  ok "反：损坏 checkpoint 时 resume 不覆盖当前工作区"
else
  bad "反：损坏 checkpoint 时 resume 不覆盖当前工作区"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
