#!/usr/bin/env bash
set -uo pipefail
HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATION="$HOOKDIR/history-migration.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/legacy/.agent"
printf '# map\n' > "$TMP/legacy/CAPABILITY-MAP.md"
printf '{}' > "$TMP/legacy/.agent/state.json"
printf '# old\n' > "$TMP/legacy/SPEC-payment.md"
OUT="$(python3 "$MIGRATION" preview "$TMP/legacy")"
printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["candidates"][0]["status"] == "unknown"; assert d["candidates"][0]["legacySpecs"] == ["SPEC-payment.md"]'
mkdir -p "$TMP/legacy/spec"
: > "$TMP/legacy/spec/CAPABILITY-HISTORY.json"
python3 "$MIGRATION" preview "$TMP/legacy" | python3 -c 'import json,sys; assert json.load(sys.stdin)["conflicts"]'
