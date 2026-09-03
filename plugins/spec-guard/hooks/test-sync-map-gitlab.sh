#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PROJECT="$WORK/project"
mkdir -p "$PROJECT/.agent" "$PROJECT/spec" "$WORK/bin"
git -C "$PROJECT" init -q

printf '%s\n' '{"tracker":"gitlab","initiative":{"title":"","issue":null,"map":"spec/CAPABILITY-MAP.md"},"issueTypes":false,"modules":{},"activeModule":"","updatedAt":""}' > "$PROJECT/.agent/state.json"
printf '%s\n' '# Capability Map: Ordered GitLab Sync' '' '## 目标' '' '验证 state 写回。' '' '## 模块' '' '| Module id | Responsibility | Depends on |' '| --- | --- | --- |' '| second | 第二个模块 | — |' '| first | 第一个模块 | — |' '' 'Build order: first → second' '' '---' '' '## 评审记录' '' '- [x] 模块边界确认' '- [x] 依赖方向单向无环' '- [x] module id 已定稿' '- [x] 构建顺序符合依赖拓扑' > "$PROJECT/spec/CAPABILITY-MAP.md"

cat > "$WORK/bin/glab" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  auth) exit 0 ;;
  repo) printf '%s\n' '{"path_with_namespace":"test/project"}' ;;
  api)
    case "$*" in
      *projects/test%2Fproject*) printf '%s\n' '{"id":1}' ;;
      *) count=0; [ -f "$GLAB_COUNTER" ] && count=$(cat "$GLAB_COUNTER"); count=$((count + 1)); printf '%s' "$count" > "$GLAB_COUNTER"; printf '{"iid":%s}\n' "$count" ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/glab"

GLAB_COUNTER="$WORK/count" PATH="$WORK/bin:$PATH" CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/sync-map-gitlab.sh" --confirm >/dev/null

python3 - "$PROJECT/.agent/state.json" <<'PY'
import json, sys
state=json.load(open(sys.argv[1]))
assert state['initiative']['title'] == 'Ordered GitLab Sync', state
assert state['initiative']['issue'] == 1, state
assert state['activeModule'] == 'first', state
assert state['modules'] == {'first': {'issue': 2}, 'second': {'issue': 3}}, state
PY

printf 'sync-map-gitlab regression passed\n'
