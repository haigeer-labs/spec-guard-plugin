#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/mcp/claude_desktop_server.mjs"
MANIFEST="$ROOT/manifest.json"
PROJECT="$(cd "$ROOT/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TEST_PROJECT="$TMP/project"
LOCAL_PROJECT="$TMP/local-project"
GITLAB_PROJECT="$TMP/gitlab-project"
mkdir -p "$TEST_PROJECT/.agent"
git -C "$TEST_PROJECT" init -q
printf '%s\n' '{"tracker":"github","initiative":{"title":"","issue":null,"map":"spec/CAPABILITY-MAP.md"},"issueTypes":false,"modules":{},"activeModule":"","updatedAt":""}' >"$TEST_PROJECT/.agent/state.json"
mkdir -p "$TEST_PROJECT/spec"
printf '%s\n' '# Capability Map: Test Preview' '' '## 目标' '' '验证 MCP 预览不会创建 Issue。' '' '## 模块' '' '| Module id | Responsibility | Depends on |' '| --- | --- | --- |' '| preview-module | 输出待创建模块 | — |' '' 'Build order: preview-module' '' '---' '' '## 评审记录' '' '- [x] 模块边界确认' '- [x] 依赖方向单向无环' '- [x] module id 已定稿' '- [x] 构建顺序符合依赖拓扑' >"$TEST_PROJECT/spec/CAPABILITY-MAP.md"
mkdir -p "$LOCAL_PROJECT/.agent" "$GITLAB_PROJECT/.agent" "$GITLAB_PROJECT/spec" "$TMP/bin"
git -C "$LOCAL_PROJECT" init -q
git -C "$GITLAB_PROJECT" init -q
printf '%s\n' '{"tracker":"none","initiative":{"title":"","issue":null,"map":"spec/CAPABILITY-MAP.md"},"issueTypes":false,"modules":{},"activeModule":"","updatedAt":""}' >"$LOCAL_PROJECT/.agent/state.json"
printf '%s\n' '{"tracker":"gitlab","initiative":{"title":"","issue":null,"map":"spec/CAPABILITY-MAP.md"},"issueTypes":false,"modules":{},"activeModule":"","updatedAt":""}' >"$GITLAB_PROJECT/.agent/state.json"
cp "$TEST_PROJECT/spec/CAPABILITY-MAP.md" "$GITLAB_PROJECT/spec/CAPABILITY-MAP.md"
printf '%s\n' '#!/usr/bin/env python3' 'import os, sys' 'args = sys.argv[1:]' 'with open(os.environ["GLAB_LOG"], "a", encoding="utf-8") as log: log.write(" ".join(args) + "\\n")' 'if args[:1] == ["repo"]: print(__import__("json").dumps({"path_with_namespace": "test/project"}))' 'if args[:1] == ["api"]: print(__import__("json").dumps({"id": 1}))' >"$TMP/bin/glab"
chmod +x "$TMP/bin/glab"

PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

run_server() {
  env -u HOME -u XDG_STATE_HOME -u XDG_CONFIG_HOME node "$SERVER" >"$TMP/stdout" 2>"$TMP/stderr" <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"test","version":"1"},"capabilities":{}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"write_operation","arguments":{"project":"/not/a/project","operation":"teardown"}}}
{"jsonrpc":"2.0","id":4,"method":"unknown/method","params":{}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"phase","arguments":{"project":"$TEST_PROJECT"}}}
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"verify_history","arguments":{"project":"$PROJECT"}}}
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"sync_map_preview","arguments":{"project":"$TEST_PROJECT"}}}
EOF
}

run_preview_server() {
  local project="$1" output="$2"
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"sync_map_preview\",\"arguments\":{\"project\":\"$project\"}}}" |
    GLAB_LOG="$TMP/glab.log" PATH="$TMP/bin:$PATH" node "$SERVER" >"$output"
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
assert [line['id'] for line in lines] == [1, 2, 3, 4, 5, 6, 7]
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
assert lines[6]['result']['isError'] is False
assert 'Initiative: Test Preview' in lines[6]['result']['content'][0]['text']
assert 'preview-module' in lines[6]['result']['content'][0]['text']
assert 'No local or remote writes were performed.' in lines[6]['result']['content'][0]['text']
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

run_preview_server "$LOCAL_PROJECT" "$TMP/local-preview"
if python3 - "$TMP/local-preview" <<'PY'
import json, sys
result=json.loads(open(sys.argv[1], encoding='utf-8').read())['result']
assert result['isError'] is False
assert 'Local tracker' in result['content'][0]['text']
PY
then
  ok "local tracker preview has no remote path"
else
  bad "local tracker preview has no remote path"
fi

run_preview_server "$GITLAB_PROJECT" "$TMP/gitlab-preview"
if python3 - "$TMP/gitlab-preview" "$TMP/glab.log" <<'PY'
import json, sys
result=json.loads(open(sys.argv[1], encoding='utf-8').read())['result']
assert result['isError'] is False
assert '将同步 initiative: Test Preview' in result['content'][0]['text']
assert '-X POST' not in open(sys.argv[2], encoding='utf-8').read()
PY
then
  ok "GitLab preview uses the deterministic no-write script"
else
  bad "GitLab preview uses the deterministic no-write script"
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

if python3 - "$MANIFEST" <<'PY'
import json, sys
manifest=json.load(open(sys.argv[1], encoding='utf-8'))
assert manifest['manifest_version'] == '0.2'
assert manifest['name'] == 'spec-guard'
assert manifest['server'] == {
  'type': 'node',
  'entry_point': 'mcp/claude_desktop_server.mjs',
  'mcp_config': {
    'command': 'node',
    'args': ['${__dirname}/mcp/claude_desktop_server.mjs'],
    'env': {},
  },
}
PY
then
  ok "Claude Desktop MCPB manifest is valid JSON"
else
  bad "Claude Desktop MCPB manifest is valid JSON"
fi

echo
echo "  总计 $PASS 通过 / $FAIL 失败"
test "$FAIL" -eq 0
