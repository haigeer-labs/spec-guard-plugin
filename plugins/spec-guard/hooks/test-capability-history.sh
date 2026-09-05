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

expect_verified() {
  if [ -f "$HISTORY" ] && python3 "$HISTORY" verify "$2" "$3" >/dev/null 2>&1; then
    ok "$1"
  else
    bad "$1"
  fi
}

expect_unverified() {
  if [ "${VERIFY_READY:-false}" = true ] && ! python3 "$HISTORY" verify "$2" "$3" >/dev/null 2>&1; then
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

PROJECT="$TMP/project"
CHECKPOINT="20260902T090000Z-0001"
mkdir -p "$PROJECT/spec/history/a/$CHECKPOINT" "$PROJECT/tasks/history/a/$CHECKPOINT/payment-api"
cat > "$PROJECT/spec/history/a/$CHECKPOINT/CAPABILITY-MAP.md" <<'EOF'
# Capability Map

## Modules

| Module id | Responsibility | Depends on |
| --- | --- | --- |
| payment-api | Payment API | — |

Build order: payment-api
EOF
printf 'spec evidence\n' > "$PROJECT/spec/history/a/$CHECKPOINT/payment-api.md"
printf 'plan evidence\n' > "$PROJECT/tasks/history/a/$CHECKPOINT/payment-api/plan.md"
MAP_SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$PROJECT/spec/history/a/$CHECKPOINT/CAPABILITY-MAP.md")"
SPEC_SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$PROJECT/spec/history/a/$CHECKPOINT/payment-api.md")"
PLAN_SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$PROJECT/tasks/history/a/$CHECKPOINT/payment-api/plan.md")"
EVIDENCE="$TMP/evidence.json"
write_history "$EVIDENCE" "{\"schemaVersion\":1,\"initiatives\":[{\"id\":\"a\",\"title\":\"A\",\"startedAt\":\"2026-09-02T09:00:00Z\",\"events\":[{\"type\":\"created\",\"at\":\"2026-09-02T09:00:00Z\",\"checkpoint\":{\"id\":\"$CHECKPOINT\",\"map\":{\"path\":\"spec/history/a/$CHECKPOINT/CAPABILITY-MAP.md\",\"sha256\":\"$MAP_SHA\"},\"modules\":[{\"id\":\"payment-api\",\"responsibility\":\"Payment API\",\"dependsOn\":[],\"status\":\"completed\",\"issue\":101,\"spec\":{\"path\":\"spec/history/a/$CHECKPOINT/payment-api.md\",\"sha256\":\"$SPEC_SHA\"},\"plan\":{\"path\":\"tasks/history/a/$CHECKPOINT/payment-api/plan.md\",\"sha256\":\"$PLAN_SHA\"}}]}}]}]}"
expect_verified "正：历史 map/spec/plan 与 SHA-256 一致" "$EVIDENCE" "$PROJECT"
VERIFY_READY=false
if python3 "$HISTORY" verify "$EVIDENCE" "$PROJECT" >/dev/null 2>&1; then VERIFY_READY=true; fi
printf 'tampered plan\n' > "$PROJECT/tasks/history/a/$CHECKPOINT/payment-api/plan.md"
expect_unverified "反：历史 plan 被篡改时校验失败" "$EVIDENCE" "$PROJECT"

AUDIT="$TMP/audit.json"
write_history "$AUDIT" "{\"schemaVersion\":1,\"initiatives\":[{\"id\":\"a\",\"title\":\"A\",\"events\":[{\"type\":\"created\",\"at\":\"legacy-now\",\"checkpoint\":{\"id\":\"$CHECKPOINT\",\"map\":{\"path\":\"spec/history/a/$CHECKPOINT/CAPABILITY-MAP.md\",\"sha256\":\"$MAP_SHA\"},\"modules\":[{\"id\":\"payment-api\",\"responsibility\":\"Guessed API\",\"dependsOn\":[\"other\"],\"status\":\"completed\",\"issue\":101,\"spec\":null,\"plan\":null}]}}]}]}"
AUDIT_BEFORE="$(shasum -a 256 "$AUDIT" | awk '{print $1}')"
python3 "$HISTORY" audit "$AUDIT" "$PROJECT" > "$TMP/audit-report.json" || exit 1
AUDIT_AFTER="$(shasum -a 256 "$AUDIT" | awk '{print $1}')"
if [ "$AUDIT_BEFORE" = "$AUDIT_AFTER" ] && python3 - "$TMP/audit-report.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
assert report["readOnly"] is True
codes = {item["code"] for item in report["findings"]}
assert {"responsibility-mismatch", "dependency-mismatch", "status-unsupported", "timestamp-unverified"} <= codes
PY
then
  ok "正：语义审计报告猜测字段且不改写账本"
else
  bad "正：语义审计报告猜测字段且不改写账本"
fi

RESUMED_AUDIT="$TMP/resumed-audit.json"
python3 - "$AUDIT" "$RESUMED_AUDIT" <<'PY'
import copy, json, sys
ledger = json.load(open(sys.argv[1], encoding="utf-8"))
events = ledger["initiatives"][0]["events"]
paused = copy.deepcopy(events[0])
paused["type"] = "paused"
paused["at"] = "legacy-paused"
events.append(paused)
events.append({"type": "resumed", "at": "legacy-resumed"})
json.dump(ledger, open(sys.argv[2], "w", encoding="utf-8"))
PY
if python3 "$HISTORY" audit "$RESUMED_AUDIT" "$PROJECT" | python3 -c 'import json,sys; report=json.load(sys.stdin); assert any(item["eventIndex"] == 2 and item["field"] == "event.at" for item in report["findings"])'; then
  ok "正：语义审计覆盖无 checkpoint 的 resumed 时间"
else
  bad "正：语义审计覆盖无 checkpoint 的 resumed 时间"
fi

CORRECTION="$TMP/correction.json"
AUDIT_REPORT_SHA="$(shasum -a 256 "$TMP/audit-report.json" | awk '{print $1}')"
write_history "$CORRECTION" "{\"type\":\"history-correction\",\"initiativeId\":\"a\",\"eventIndex\":0,\"checkpointId\":\"$CHECKPOINT\",\"moduleId\":\"payment-api\",\"field\":\"status\",\"before\":\"completed\",\"after\":\"unknown\",\"auditedAt\":\"2026-09-05T12:00:00Z\",\"auditReportSha256\":\"$AUDIT_REPORT_SHA\",\"sources\":[{\"kind\":\"audit-finding\",\"code\":\"status-unsupported\"}]}"
CORRECTION_BEFORE="$(shasum -a 256 "$AUDIT" | awk '{print $1}')"
if python3 "$HISTORY" correct --confirm "$AUDIT" "$TMP/audit-report.json" "$CORRECTION" >/dev/null 2>&1 \
  && python3 "$HISTORY" validate "$AUDIT" >/dev/null 2>&1 \
  && python3 - "$AUDIT" <<'PY'
import json, sys
ledger = json.load(open(sys.argv[1], encoding="utf-8"))
assert ledger["initiatives"][0]["events"][0]["checkpoint"]["modules"][0]["status"] == "completed"
assert ledger["corrections"][0]["after"] == "unknown"
PY
then
  ok "正：确认的修正只追加证据事件，不重写 checkpoint"
else
  bad "正：确认的修正只追加证据事件，不重写 checkpoint"
fi
CORRECTION_AFTER="$(shasum -a 256 "$AUDIT" | awk '{print $1}')"
BAD_CORRECTION="$TMP/bad-correction.json"
write_history "$BAD_CORRECTION" "{\"type\":\"history-correction\",\"initiativeId\":\"a\",\"eventIndex\":0,\"checkpointId\":\"$CHECKPOINT\",\"moduleId\":\"payment-api\",\"field\":\"status\",\"before\":\"completed\",\"after\":\"completed\",\"auditedAt\":\"2026-09-05T12:00:00Z\",\"auditReportSha256\":\"$AUDIT_REPORT_SHA\",\"sources\":[{\"kind\":\"audit-finding\",\"code\":\"status-unsupported\"}]}"
if [ "$CORRECTION_BEFORE" != "$CORRECTION_AFTER" ] \
  && ! python3 "$HISTORY" correct "$AUDIT" "$TMP/audit-report.json" "$BAD_CORRECTION" >/dev/null 2>&1 \
  && ! python3 "$HISTORY" correct --confirm "$AUDIT" "$TMP/audit-report.json" "$BAD_CORRECTION" >/dev/null 2>&1 \
  && [ "$CORRECTION_AFTER" = "$(shasum -a 256 "$AUDIT" | awk '{print $1}')" ]; then
  ok "反：未确认或把 unknown 升级为完成的修正均不写入"
else
  bad "反：未确认或把 unknown 升级为完成的修正均不写入"
fi
INVALID_LEDGER="$TMP/invalid-correction-ledger.json"
python3 - "$AUDIT" "$INVALID_LEDGER" <<'PY'
import json, sys
ledger = json.load(open(sys.argv[1], encoding="utf-8"))
ledger["corrections"][0]["eventIndex"] = 99
json.dump(ledger, open(sys.argv[2], "w", encoding="utf-8"))
PY
if ! python3 "$HISTORY" validate "$INVALID_LEDGER" >/dev/null 2>&1; then
  ok "反：补正引用不存在的事件时 schema 拒绝账本"
else
  bad "反：补正引用不存在的事件时 schema 拒绝账本"
fi

NEW_INIT="$TMP/new-initiative.json"
write_history "$NEW_INIT" '{"id":"new","title":"New","startedAt":"2026-09-02T09:00:00Z","events":[{"type":"created","at":"2026-09-02T09:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/new/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}}]}'
LEDGER="$TMP/ledger.json"
if [ -f "$HISTORY" ] && python3 "$HISTORY" create "$LEDGER" "$NEW_INIT" >/dev/null 2>&1; then
  ok "正：可从 created initiative 原子创建账本"
  CREATE_READY=true
else
  bad "正：可从 created initiative 原子创建账本"
  CREATE_READY=false
fi
if [ "$CREATE_READY" = true ] && python3 "$HISTORY" validate "$LEDGER" >/dev/null 2>&1; then
  ok "正：新建账本立即可读"
else
  bad "正：新建账本立即可读"
fi
PAUSE="$TMP/pause.json"
write_history "$PAUSE" '{"type":"paused","at":"2026-09-03T09:00:00Z","checkpoint":{"id":"20260903T090000Z-0002","map":{"path":"spec/history/new/20260903T090000Z-0002/CAPABILITY-MAP.md","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"modules":[]}}'
if [ "$CREATE_READY" = true ] && python3 "$HISTORY" append "$LEDGER" new "$PAUSE" >/dev/null 2>&1 \
  && [ "$(python3 "$HISTORY" status "$LEDGER" new 2>/dev/null || true)" = "paused" ]; then
  ok "正：追加合法事件并更新派生状态"
  APPEND_READY=true
else
  bad "正：追加合法事件并更新派生状态"
  APPEND_READY=false
fi
BEFORE="$(shasum -a 256 "$LEDGER" 2>/dev/null | awk '{print $1}')"
if [ "$APPEND_READY" = true ] && ! python3 "$HISTORY" append "$LEDGER" new "$NEW_INIT" >/dev/null 2>&1 \
  && [ "$BEFORE" = "$(shasum -a 256 "$LEDGER" | awk '{print $1}')" ]; then
  ok "反：非法追加不改写原账本"
else
  bad "反：非法追加不改写原账本"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
