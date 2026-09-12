#!/usr/bin/env bash
# GitLab 能力图投影的确定性入口；身份、恢复与 state 写回只在共享 Python helper 中实现。
set -euo pipefail

confirm=false
[ "${1:-}" = "--confirm" ] && { confirm=true; shift; }
[ "$#" -eq 0 ] || { echo 'usage: sync-map-gitlab.sh [--confirm]' >&2; exit 2; }

hooks="$(cd "$(dirname "$0")" && pwd)"
project="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
set --
"$confirm" && set -- --confirm

python3 "$hooks/gitlab_tracker.py" sync \
  --project "$project" \
  --map "$project/spec/CAPABILITY-MAP.md" \
  --state "$project/.agent/state.json" \
  "$@"
