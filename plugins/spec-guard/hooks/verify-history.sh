#!/usr/bin/env bash
set -uo pipefail

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "usage: verify-history.sh <project>" >&2; exit 2; }
LEDGER="$PROJECT/spec/CAPABILITY-HISTORY.json"
[ -f "$LEDGER" ] || { echo "未验证：没有 capability history ledger"; exit 0; }
ROOT="$(cd "$(dirname "$0")" && pwd)"
python3 "$ROOT/capability-history.py" verify "$LEDGER" "$PROJECT" || exit 1
python3 - "$LEDGER" "$PROJECT" <<'PY'
import json, os, sys
ledger, project = sys.argv[1:]
data = json.load(open(ledger, encoding="utf-8"))
expected = set()
for initiative in data["initiatives"]:
    for event in initiative["events"]:
        checkpoint = event.get("checkpoint")
        if checkpoint:
            expected.add(os.path.dirname(checkpoint["map"]["path"]))
for base in ("spec/history", "tasks/history", ".agent/history"):
    root = os.path.join(project, base)
    if not os.path.isdir(root):
        continue
    for directory, _, files in os.walk(root):
        if not files:
            continue
        relative = os.path.relpath(directory, project)
        if base == "spec/history" and relative not in expected:
            raise SystemExit("orphan history evidence: " + relative)
PY
echo "历史证据校验通过"
