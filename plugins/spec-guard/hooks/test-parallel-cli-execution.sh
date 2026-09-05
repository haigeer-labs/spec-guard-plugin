#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/worktree"
python3 - "$ROOT/hooks" "$WORK/worktree" <<'PY'
import sys
hooks, worktree = sys.argv[1:]
sys.path.insert(0, hooks)
from parallel_cli_adapters import LedgerError, command_for  # noqa: F401

codex = command_for("codex-cli", worktree, "codex")
assert codex == ["codex", "-C", worktree], codex
claude = command_for("claude-cli", worktree, "claude")
assert claude == ["claude"], claude
for host in ("desktop", "unknown"):
    try:
        command_for(host, worktree, "tool")
    except LedgerError:
        pass
    else:
        raise AssertionError("unsupported host accepted")
PY
printf 'parallel-cli-execution regression passed\n'
