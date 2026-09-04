#!/bin/bash
# parallel-execution-ledger 的确定性回归：身份、路径与 schema 基元。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git init -q "$WORK/project"
git -C "$WORK/project" config user.email test@example.invalid
git -C "$WORK/project" config user.name test
printf 'fixture\n' > "$WORK/project/README.md"
git -C "$WORK/project" add README.md
git -C "$WORK/project" commit -qm fixture

python3 - "$ROOT/hooks" "$WORK/project" <<'PY'
import os
import subprocess
import sys

hooks, project = sys.argv[1:]
sys.path.insert(0, hooks)

from parallel_execution_lib import (  # noqa: F401
    LedgerError,
    ledger_root,
    run_id,
    validate_module_id,
    validate_record,
)

common_dir = subprocess.check_output(
    ["git", "-C", project, "rev-parse", "--git-common-dir"], text=True
).strip()
if not os.path.isabs(common_dir):
    common_dir = os.path.abspath(os.path.join(project, common_dir))

assert ledger_root(project) == os.path.join(common_dir, "spec-guard", "parallel", "v1")

inputs = ("git@github.com:owner/repo.git", "a" * 40, "goal-digest", ["a", "b"])
assert run_id(*inputs) == run_id(*inputs)
assert run_id("https://github.com/owner/repo.git", *inputs[1:]) == run_id(*inputs)
assert run_id("git@github.com:owner/other.git", *inputs[1:]) != run_id(*inputs)
assert run_id(inputs[0], "b" * 40, *inputs[2:]) != run_id(*inputs)

for module_id in ("alpha", "parallel-execution-ledger", "oauth2"):
    validate_module_id(module_id)
for module_id in ("", "Alpha", "bad_id", "../escape", "alpha/"):
    try:
        validate_module_id(module_id)
    except LedgerError:
        pass
    else:
        raise AssertionError("invalid module id accepted: %r" % module_id)

valid = {"schemaVersion": 1, "runId": run_id(*inputs), "baseSha": "a" * 40}
validate_record(valid, ("schemaVersion", "runId", "baseSha"))
for record in ({}, {"schemaVersion": 2, "runId": "x", "baseSha": "a" * 40}, dict(valid, baseSha="short")):
    try:
        validate_record(record, ("schemaVersion", "runId", "baseSha"))
    except LedgerError:
        pass
    else:
        raise AssertionError("invalid record accepted: %r" % record)
PY

printf 'parallel-execution-ledger regression passed\n'
