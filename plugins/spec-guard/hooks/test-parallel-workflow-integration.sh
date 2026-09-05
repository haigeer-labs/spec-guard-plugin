#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT/commands/parallel-execute.md" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
for required in (
    "未得到本次明确确认时",
    "parallel-safety-gate.py",
    "--format json",
    "parallel-execution.py\" create-run",
    "parallel-worktree.py\" provision",
    "eligible group 在确认后变化",
    "不得重试 unknown worker",
):
    assert required in text, required
assert "parallel-cli.py\" start" not in text
assert text.index("阶段一：只读预览") < text.index("阶段二：确认后执行")
PY

printf 'parallel-workflow-integration regression passed\n'
