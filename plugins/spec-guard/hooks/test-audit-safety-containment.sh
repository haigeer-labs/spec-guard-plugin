#!/bin/bash
# audit-safety-containment：危险并行写入口必须在产生副作用前拒绝。
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
import json
import importlib.util
import os
import subprocess
import sys

hooks, project = sys.argv[1:]
sys.path.insert(0, hooks)

from parallel_execution_lib import (ParallelWritesDisabled, claim_lease, ledger_root,
                                    run_id)
spec = importlib.util.spec_from_file_location("parallel_execution_test", os.path.join(hooks, "parallel-execution.py"))
parallel_execution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parallel_execution)
claim_module = parallel_execution.claim_module
create_run = parallel_execution.create_run

head = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
root = ledger_root(project)
run = {"schemaVersion": 1, "runId": run_id("git@github.com:owner/repo.git", head, "goal", ["alpha"]),
       "baseSha": head, "goalDigest": "goal", "modules": [{"id": "alpha", "rowDigest": "alpha"}]}

def snapshot():
    found = []
    for base, _dirs, files in os.walk(os.path.dirname(root)):
        for name in files:
            path = os.path.join(base, name)
            found.append((os.path.relpath(path, project), open(path, "rb").read()))
    return sorted(found)

before = snapshot()
for action in (
        lambda: create_run(project, os.path.join(project, "missing-report.json")),
        lambda: claim_module(project, run["runId"], "alpha"),
        lambda: claim_lease(root, run, "alpha")):
    try:
        action()
    except ParallelWritesDisabled as error:
        assert error.code == "PARALLEL_WRITES_DISABLED", error.code
    else:
        raise AssertionError("parallel write was not disabled")
    assert snapshot() == before, "disabled write changed the fixture"

script = os.path.join(hooks, "parallel-execution.py")
for arguments in (
        ["create-run", "--project", project, "--safety-report", os.path.join(project, "missing-report.json"), "--format", "json"],
        ["claim-module", "--project", project, "--run", run["runId"], "--module", "alpha", "--format", "json"]):
    result = subprocess.run([sys.executable, script] + arguments, capture_output=True, text=True)
    assert result.returncode == 1, result
    payload = json.loads(result.stdout)
    assert payload == {"ok": False, "code": "PARALLEL_WRITES_DISABLED",
                       "message": "实验性并行写操作已暂停；已有成果保留，请使用只读状态检查。"}, payload
    assert result.stderr == "", result.stderr
    assert snapshot() == before, "disabled CLI write changed the fixture"
PY

printf 'audit-safety-containment regression passed\n'
