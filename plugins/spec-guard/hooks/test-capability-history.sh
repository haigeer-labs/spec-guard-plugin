#!/usr/bin/env bash
# capability-history.py 的账本协议回归：先固定事件流与 schema，再实现读写工具。
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTORY="$HOOKDIR/capability-history.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok() { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }

write_history() {
  printf '%s\n' "$2" > "$1"
}

expect_valid() {
  if [ -f "$HISTORY" ] && python3 "$HISTORY" validate "$2" >/dev/null 2>&1; then
    ok "$1"
  else
    bad "$1"
  fi
}

expect_invalid() {
  if [ -f "$HISTORY" ] && ! python3 "$HISTORY" validate "$2" >/dev/null 2>&1; then
    ok "$1"
  else
    bad "$1"
  fi
}

echo "═══ Capability history ledger regression ═══"

VALID="$TMP/valid.json"
write_history "$VALID" '{
  "schemaVersion": 1,
  "initiatives": [{
    "id": "payment-v2",
    "title": "Payment v2",
    "startedAt": "2026-09-02T09:00:00Z",
    "tracker": {"kind": "github", "initiativeIssue": 100},
    "events": [
      {"type": "created", "at": "2026-09-02T09:00:00Z", "checkpoint": {
        "id": "20260902T090000Z-0001",
        "map": {"path": "spec/history/payment-v2/20260902T090000Z-0001/CAPABILITY-MAP.md", "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
        "modules": [{"id": "payment-api", "responsibility": "Payment API", "dependsOn": [], "status": "not-started", "issue": 101, "spec": null, "plan": null}]
      }},
      {"type": "paused", "at": "2026-09-03T09:00:00Z", "checkpoint": {
        "id": "20260903T090000Z-0002",
        "map": {"path": "spec/history/payment-v2/20260903T090000Z-0002/CAPABILITY-MAP.md", "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
        "modules": [{"id": "payment-api", "responsibility": "Payment API", "dependsOn": [], "status": "in-progress", "issue": 101, "spec": null, "plan": null}]
      }},
      {"type": "resumed", "at": "2026-09-04T09:00:00Z"},
      {"type": "completed", "at": "2026-09-05T09:00:00Z", "checkpoint": {
        "id": "20260905T090000Z-0003",
        "map": {"path": "spec/history/payment-v2/20260905T090000Z-0003/CAPABILITY-MAP.md", "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},
        "modules": [{"id": "payment-api", "responsibility": "Payment API", "dependsOn": [], "status": "completed", "issue": 101, "spec": null, "plan": null}]
      }}
    ]
  }]
}'
expect_valid "正：created → paused → resumed → completed 合法" "$VALID"

if [ -f "$HISTORY" ] && [ "$(python3 "$HISTORY" status "$VALID" payment-v2 2>/dev/null || true)" = "completed" ]; then
  ok "正：最后事件推导 initiative 状态"
else
  bad "正：最后事件推导 initiative 状态"
fi

BAD_FIRST="$TMP/bad-first.json"
write_history "$BAD_FIRST" '{"schemaVersion":1,"initiatives":[{"id":"a","title":"A","startedAt":"2026-09-02T09:00:00Z","events":[{"type":"paused","at":"2026-09-02T09:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/a/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}}]}]}'
expect_invalid "反：首事件不是 created 被拒绝" "$BAD_FIRST"

BAD_FLOW="$TMP/bad-flow.json"
write_history "$BAD_FLOW" '{"schemaVersion":1,"initiatives":[{"id":"a","title":"A","startedAt":"2026-09-02T09:00:00Z","events":[{"type":"created","at":"2026-09-02T09:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/a/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}},{"type":"resumed","at":"2026-09-03T09:00:00Z"}]}]}'
expect_invalid "反：未暂停直接 resumed 被拒绝" "$BAD_FLOW"

BAD_MODULES="$TMP/bad-modules.json"
write_history "$BAD_MODULES" '{"schemaVersion":1,"initiatives":[{"id":"a","title":"A","startedAt":"2026-09-02T09:00:00Z","events":[{"type":"created","at":"2026-09-02T09:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/a/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[{"id":"same","responsibility":"one","dependsOn":[],"status":"not-started","issue":null,"spec":null,"plan":null},{"id":"same","responsibility":"two","dependsOn":[],"status":"not-started","issue":null,"spec":null,"plan":null}]}}]}]}'
expect_invalid "反：同一 checkpoint 重复 module id 被拒绝" "$BAD_MODULES"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
