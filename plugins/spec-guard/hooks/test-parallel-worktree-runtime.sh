#!/bin/bash
# parallel-worktree-runtime 的真实 Git 夹具：身份与受控路径基础。
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
import os
import subprocess
import sys

hooks, project = sys.argv[1:]
sys.path.insert(0, hooks)

from parallel_execution_lib import ParallelWritesDisabled, ledger_root
from parallel_worktree_lib import LedgerError, load_worker_manifest, provision, reclaim, validate_worker_manifest, verify_worker, worker_manifest_path, worker_path  # noqa: F401
from test_parallel_fixture import materialize_worker, verify_fixture_worker

head = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
common = subprocess.check_output(["git", "-C", project, "rev-parse", "--git-common-dir"], text=True).strip()
if not os.path.isabs(common):
    common = os.path.abspath(os.path.join(project, common))
worker = "a" * 12 + "-alpha-1"
manifest = {
    "schemaVersion": 1,
    "runId": "a" * 64,
    "workerId": worker,
    "moduleId": "alpha",
    "baseSha": head,
    "owner": "spec-guard",
    "gitCommonDir": common,
    "worktreePath": worker_path(project, worker),
    "branch": "spec-guard/" + worker,
}
validate_worker_manifest(project, manifest)
for field, value in (("owner", "host"), ("gitCommonDir", common + "-other"),
                     ("worktreePath", os.path.join(project, "outside"))):
    invalid = dict(manifest, **{field: value})
    try:
        validate_worker_manifest(project, invalid)
    except LedgerError:
        pass
    else:
        raise AssertionError("invalid manifest accepted: %s" % field)
stale = dict(manifest, baseSha="b" * 40)
validate_worker_manifest(project, stale)
try:
    provision(project, stale)
except ParallelWritesDisabled:
    pass
else:
    raise AssertionError("stale worker provision was not disabled")

created = materialize_worker(project, manifest)
assert created["worktreePath"] == manifest["worktreePath"], created
assert os.path.isdir(created["worktreePath"]), created
assert load_worker_manifest(project, worker) == created
assert subprocess.check_output(["git", "-C", created["worktreePath"], "rev-parse", "HEAD"], text=True).strip() == head
assert subprocess.check_output(["git", "-C", created["worktreePath"], "branch", "--show-current"], text=True).strip() == manifest["branch"]
healthy = verify_worker(project, created)
assert healthy["ok"] is True and healthy["state"] == "ready", healthy
cli = os.path.join(hooks, "parallel-worktree.py")
verified = json.loads(subprocess.check_output(["python3", cli, "verify", "--project", project,
                                                "--worker", worker, "--format", "json"], text=True))
assert verified["ok"] is True and verified["state"] == "ready", verified
try:
    provision(project, manifest)
except ParallelWritesDisabled:
    pass
else:
    raise AssertionError("duplicate worker provision was not disabled")

with open(created["worktreePath"] + "/README.md", "a", encoding="utf-8") as handle:
    handle.write("worker dirty\n")
dirty_worker = verify_worker(project, created)
assert dirty_worker["ok"] is False and dirty_worker["state"] == "unknown", dirty_worker
subprocess.check_call(["git", "-C", created["worktreePath"], "checkout", "--", "README.md"])
for candidate, merged, confirm in ((created, False, False), (dict(created, owner="host"), True, False)):
    try:
        reclaim(project, candidate, merged=merged, confirm=confirm)
    except ParallelWritesDisabled:
        pass
    else:
        raise AssertionError("worktree reclaim was not disabled")
assert os.path.lexists(created["worktreePath"]), "disabled reclaim removed a worktree"
assert load_worker_manifest(project, worker) == created

# Worker 提交后仍须证明 branch 从初始 base 演进；首次汇合后也必须能安全回收。
progressed = dict(manifest, runId="d" * 64, workerId="d" * 12 + "-alpha-1")
progressed["worktreePath"] = worker_path(project, progressed["workerId"])
progressed["branch"] = "spec-guard/" + progressed["workerId"]
progressed = materialize_worker(project, progressed)
# The fixture checker must reject missing resources and wrong identities.
for field, value in (("worktreePath", progressed["worktreePath"] + "-missing"),
                     ("branch", "wrong-fixture-branch"), ("baseSha", "0" * 40)):
    try:
        verify_fixture_worker(project, dict(progressed, **{field: value}))
    except AssertionError:
        pass
    else:
        raise AssertionError("broken fixture accepted: " + field)
with open(progressed["worktreePath"] + "/README.md", "a", encoding="utf-8") as handle:
    handle.write("worker committed\n")
subprocess.check_call(["git", "-C", progressed["worktreePath"], "add", "README.md"])
subprocess.check_call(["git", "-C", progressed["worktreePath"], "commit", "-qm", "worker commit"])
worker_head = subprocess.check_output(["git", "-C", progressed["worktreePath"], "rev-parse", "HEAD"], text=True).strip()
assert worker_head != head
progressed_status = verify_worker(project, progressed)
assert progressed_status["ok"] is True and progressed_status["workerHead"] == worker_head, progressed_status
try:
    reclaim(project, progressed, merged=True, confirm=False)
except ParallelWritesDisabled:
    pass
else:
    raise AssertionError("merged worktree reclaim was not disabled")
assert os.path.lexists(progressed["worktreePath"]), "disabled merged reclaim removed a worktree"

run_id = "c" * 64
current = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
run = {"schemaVersion": 1, "runId": run_id, "baseSha": current, "goalDigest": "fixture",
       "modules": [{"id": "beta", "rowDigest": "fixture"}]}
from test_parallel_fixture import write_record
write_record(os.path.join(ledger_root(project), "runs", run_id + ".json"), run)
provision_target = worker_path(project, run_id[:12] + "-beta-1")
blocked = subprocess.run(["python3", cli, "provision", "--project", project,
                           "--run", run_id, "--module", "beta", "--format", "json"],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
assert blocked.returncode == 1 and json.loads(blocked.stdout)["code"] == "PARALLEL_WRITES_DISABLED", blocked.stdout
assert blocked.stderr == "", blocked.stderr
assert not os.path.lexists(provision_target), "disabled provision created a worktree"

started = dict(manifest, runId=run_id, workerId=run_id[:12] + "-beta-1", moduleId="beta", baseSha=current)
started["worktreePath"] = provision_target
started["branch"] = "spec-guard/" + started["workerId"]
started = materialize_worker(project, started)
reclaimed_cli = subprocess.run(["python3", cli, "reclaim", "--project", project,
                                "--worker", started["workerId"], "--confirm",
                                "--format", "json"], stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
assert reclaimed_cli.returncode == 1, reclaimed_cli
assert json.loads(reclaimed_cli.stdout)["code"] == "PARALLEL_WRITES_DISABLED", reclaimed_cli.stdout
assert reclaimed_cli.stderr == "", reclaimed_cli.stderr
assert os.path.lexists(started["worktreePath"]), "disabled CLI reclaim removed a worktree"
with open(worker_manifest_path(project, started["workerId"]), "w", encoding="utf-8") as handle:
    handle.write("{")
corrupt = subprocess.run(["python3", cli, "verify", "--project", project,
                          "--worker", started["workerId"]], stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
assert corrupt.returncode != 0 and "账本记录" in corrupt.stderr, corrupt.stderr

with open(project + "/README.md", "a", encoding="utf-8") as handle:
    handle.write("dirty\n")
dirty = dict(manifest, workerId="b" * 12 + "-alpha-1")
dirty["worktreePath"] = worker_path(project, dirty["workerId"])
dirty["branch"] = "spec-guard/" + dirty["workerId"]
try:
    provision(project, dirty)
except ParallelWritesDisabled:
    pass
else:
    raise AssertionError("dirty source worktree provision was not disabled")
PY

printf 'parallel-worktree-runtime regression passed\n'
