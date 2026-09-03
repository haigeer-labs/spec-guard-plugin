#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/mcp/claude_desktop_server.py"
PROJECT="$(cd "$ROOT/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TEST_PROJECT="$TMP/project"
mkdir -p "$TEST_PROJECT/.agent"
git -C "$TEST_PROJECT" init -q
printf '%s\n' '{"tracker":"github","initiative":{"title":"","issue":null,"map":"spec/CAPABILITY-MAP.md"},"issueTypes":false,"modules":{},"activeModule":"","updatedAt":""}' >"$TEST_PROJECT/.agent/state.json"

PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

run_server() {
  env -u HOME -u XDG_STATE_HOME -u XDG_CONFIG_HOME python3 "$SERVER" >"$TMP/stdout" 2>"$TMP/stderr" <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"test","version":"1"},"capabilities":{}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"write_operation","arguments":{"project":"/not/a/project","operation":"teardown"}}}
{"jsonrpc":"2.0","id":4,"method":"unknown/method","params":{}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"phase","arguments":{"project":"$TEST_PROJECT"}}}
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"verify_history","arguments":{"project":"$PROJECT"}}}
EOF
}

echo "═══ Claude Desktop MCP 回归测试 ═══"

if run_server; then
  ok "server accepts JSON-RPC stream"
else
  bad "server accepts JSON-RPC stream"
fi

if python3 - "$TMP/stdout" <<'PY'
import json, sys
lines=[json.loads(line) for line in open(sys.argv[1], encoding='utf-8') if line.strip()]
assert [line['id'] for line in lines] == [1, 2, 3, 4, 5, 6]
assert lines[0]['result']['protocolVersion'] == '2025-06-18'
assert lines[0]['result']['capabilities'] == {'tools': {}}
assert [tool['name'] for tool in lines[1]['result']['tools']] == [
    'phase', 'verify', 'verify_history', 'sync_map_preview', 'write_operation'
]
assert lines[2]['result']['isError'] is True
assert 'not execute' in lines[2]['result']['content'][0]['text']
assert lines[3]['error']['code'] == -32601
assert lines[4]['result']['isError'] is False
assert 'hookSpecificOutput' in lines[4]['result']['content'][0]['text']
assert lines[5]['result']['isError'] is False
assert '历史证据校验通过' in lines[5]['result']['content'][0]['text']
PY
then
  ok "protocol, safe write response, and read-only hook tools"
else
  bad "protocol, safe write response, and read-only hook tools"
fi

if test ! -e "$TEST_PROJECT/.local"; then
  ok "hooks do not create local state inside the project"
else
  bad "hooks do not create local state inside the project"
fi

if python3 - "$TMP/stdout" <<'PY'
import json, sys
for line in open(sys.argv[1], encoding='utf-8'):
    json.loads(line)
PY
then
  ok "stdout contains JSON-RPC only"
else
  bad "stdout contains JSON-RPC only"
fi

echo
echo "  总计 $PASS 通过 / $FAIL 失败"
test "$FAIL" -eq 0
