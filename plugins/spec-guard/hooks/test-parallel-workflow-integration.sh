#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT/commands/parallel-execute.md" "$ROOT/commands/parallel-status.md" "$ROOT/commands/parallel-integrate.md" "$ROOT/commands/parallel-reclaim.md" <<'PY'
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

integrate = open(sys.argv[3], encoding="utf-8").read()
for required in (
    "每次只处理一个 module",
    "本次明确确认",
    "parallel-execution.py\" status",
    "parallel-worktree.py\" verify",
    "parallel-cli.py\" inspect",
    "get(\"state\") != \"completed\"",
    "git -C \"$PROJECT\" merge-base --is-ancestor \"$BASE_SHA\" \"$BRANCH\"",
    "git -C \"$PROJECT\" merge --no-ff \"$BRANCH\"",
    "base SHA 与当前默认分支 HEAD 不一致",
):
    assert required in integrate, required
for forbidden in ("while IFS= read", " create-run", " provision", " reclaim", "\" start"):
    assert forbidden not in integrate, forbidden

reclaim = open(sys.argv[4], encoding="utf-8").read()
for required in (
    "本次明确确认",
    "parallel-execution.py\" status",
    "parallel-worktree.py\" verify",
    "parallel-cli.py\" inspect",
    "merge-base --is-ancestor",
    "--merged",
    "--confirm",
    "MODE=discard",
    "MODE=merged",
    "明确 discard",
):
    assert required in reclaim, required
for forbidden in ("git -C \"$PROJECT\" worktree remove", "git -C \"$PROJECT\" branch -D",
                  " create-run", " provision", "\" start"):
    assert forbidden not in reclaim, forbidden
PY

printf 'parallel-workflow-integration regression passed\n'
