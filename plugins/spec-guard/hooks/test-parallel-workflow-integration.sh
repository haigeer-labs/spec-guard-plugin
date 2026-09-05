#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT/commands/parallel-execute.md" "$ROOT/commands/parallel-status.md" <<'PY'
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

status = open(sys.argv[2], encoding="utf-8").read()
for required in ("这是只读命令", "parallel-execution.py\" status", "parallel-worktree.py\" verify",
                 "parallel-cli.py\" inspect", "unknown worker"):
    assert required in status, required
for forbidden in (" create-run", " provision", " reclaim", "\" start"):
    assert forbidden not in status, forbidden

for path in ("next.md", "deliver.md"):
    command = open(sys.argv[1].replace("parallel-execute.md", path), encoding="utf-8").read()
    for required in ("spec-guard/<worker-id>", "parallel-worktree.py verify", "moduleId",
                     "不得继续执行下面的 canonical", "activeModule"):
        assert required in command, (path, required)
PY

printf 'parallel-workflow-integration regression passed\n'
