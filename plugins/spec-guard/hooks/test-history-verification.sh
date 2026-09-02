#!/usr/bin/env bash
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTORY="$HOOKDIR/capability-history.py"
VERIFY="$HOOKDIR/verify-history.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PROJECT="$TMP/project"
CP="20260902T090000Z-0001"
mkdir -p "$PROJECT/spec/history/a/$CP" "$PROJECT/.agent/history/a/$CP"
printf 'map\n' > "$PROJECT/spec/history/a/$CP/CAPABILITY-MAP.md"
printf '{}\n' > "$PROJECT/.agent/history/a/$CP/state.json"
MAP="$(shasum -a 256 "$PROJECT/spec/history/a/$CP/CAPABILITY-MAP.md" | awk '{print $1}')"
STATE="$(shasum -a 256 "$PROJECT/.agent/history/a/$CP/state.json" | awk '{print $1}')"
LEDGER="$PROJECT/spec/CAPABILITY-HISTORY.json"
printf '%s\n' "{\"schemaVersion\":1,\"initiatives\":[{\"id\":\"a\",\"title\":\"A\",\"events\":[{\"type\":\"created\",\"at\":\"now\",\"checkpoint\":{\"id\":\"$CP\",\"map\":{\"path\":\"spec/history/a/$CP/CAPABILITY-MAP.md\",\"sha256\":\"$MAP\"},\"state\":{\"path\":\".agent/history/a/$CP/state.json\",\"sha256\":\"$STATE\"},\"modules\":[]}}]}]}" > "$LEDGER"
"$HISTORY" verify "$LEDGER" "$PROJECT" >/dev/null || exit 1
printf 'tampered\n' > "$PROJECT/.agent/history/a/$CP/state.json"
! "$HISTORY" verify "$LEDGER" "$PROJECT" >/dev/null 2>&1
rm -f "$LEDGER"
"$VERIFY" "$PROJECT" | grep -q '未验证'
printf '%s\n' '{"schemaVersion":1,"initiatives":[]}' > "$LEDGER"
mkdir -p "$PROJECT/spec/history/orphan/20260902T090000Z-0001"
printf 'orphan\n' > "$PROJECT/spec/history/orphan/20260902T090000Z-0001/CAPABILITY-MAP.md"
! "$VERIFY" "$PROJECT" >/dev/null 2>&1
