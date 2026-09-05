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
import parallel_worktree_lib
from test_parallel_fixture import materialize_worker
spec = importlib.util.spec_from_file_location("parallel_execution_test", os.path.join(hooks, "parallel-execution.py"))
parallel_execution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parallel_execution)
claim_module = parallel_execution.claim_module
create_run = parallel_execution.create_run
worktree_spec = importlib.util.spec_from_file_location("parallel_worktree_test", os.path.join(hooks, "parallel-worktree.py"))
parallel_worktree = importlib.util.module_from_spec(worktree_spec)
worktree_spec.loader.exec_module(parallel_worktree)

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


worker_id = "b" * 12 + "-beta-1"
common = subprocess.check_output(["git", "-C", project, "rev-parse", "--git-common-dir"], text=True).strip()
if not os.path.isabs(common):
    common = os.path.abspath(os.path.join(project, common))
worker = materialize_worker(project, {
    "schemaVersion": 1,
    "runId": "b" * 64,
    "workerId": worker_id,
    "moduleId": "beta",
    "baseSha": head,
    "owner": "spec-guard",
    "gitCommonDir": common,
    "worktreePath": parallel_worktree_lib.worker_path(project, worker_id),
    "branch": "spec-guard/" + worker_id,
})

def worker_snapshot():
    manifest_path = parallel_worktree_lib.worker_manifest_path(project, worker_id)
    return {
        "manifest": open(manifest_path, "rb").read(),
        "readme": open(os.path.join(worker["worktreePath"], "README.md"), "rb").read(),
        "branch": subprocess.run(["git", "-C", project, "rev-parse", "--verify",
                                  "refs/heads/" + worker["branch"]], capture_output=True,
                                 text=True).returncode,
    }

worker_before = worker_snapshot()
original_git = parallel_worktree_lib._git
parallel_worktree_lib._git = lambda *_args: (_ for _ in ()).throw(AssertionError("Git command reached"))
try:
    for action in (
            lambda: parallel_worktree_lib.provision(project, worker),
            lambda: parallel_worktree.provision_worker(project, "c" * 64, "beta"),
            lambda: parallel_worktree_lib.reclaim(project, worker, merged=True, confirm=True),
            lambda: parallel_worktree.reclaim_worker(project, worker_id, merged=True, confirm=True)):
        try:
            action()
        except ParallelWritesDisabled as error:
            assert error.code == "PARALLEL_WRITES_DISABLED", error.code
        else:
            raise AssertionError("worktree write was not disabled")
        assert worker_snapshot() == worker_before, "disabled worktree write changed the fixture"
finally:
    parallel_worktree_lib._git = original_git

worktree_script = os.path.join(hooks, "parallel-worktree.py")
for arguments in (
        ["provision", "--project", project, "--run", "c" * 64, "--module", "beta", "--format", "json"],
        ["reclaim", "--project", project, "--worker", worker_id, "--merged", "--confirm", "--format", "json"]):
    result = subprocess.run([sys.executable, worktree_script] + arguments, capture_output=True, text=True)
    assert result.returncode == 1, result
    payload = json.loads(result.stdout)
    assert payload == {"ok": False, "code": "PARALLEL_WRITES_DISABLED",
                       "message": "实验性并行写操作已暂停；已有成果保留，请使用只读状态检查。"}, payload
    assert result.stderr == "", result.stderr
    assert worker_snapshot() == worker_before, "disabled worktree CLI changed the fixture"
PY

printf 'audit-safety-containment regression passed\n'
