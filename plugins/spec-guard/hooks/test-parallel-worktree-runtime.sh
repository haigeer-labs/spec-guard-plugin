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

from parallel_execution_lib import ledger_root, write_json_exclusive
from parallel_worktree_lib import LedgerError, load_worker_manifest, provision, reclaim, validate_worker_manifest, verify_worker, worker_manifest_path, worker_path  # noqa: F401

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
                     ("worktreePath", os.path.join(project, "outside")), ("baseSha", "b" * 40)):
    invalid = dict(manifest, **{field: value})
    try:
        validate_worker_manifest(project, invalid)
    except LedgerError:
        pass
    else:
        raise AssertionError("invalid manifest accepted: %s" % field)

created = provision(project, manifest)
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
except LedgerError:
    pass
else:
    raise AssertionError("duplicate worker provision accepted")

with open(created["worktreePath"] + "/README.md", "a", encoding="utf-8") as handle:
    handle.write("worker dirty\n")
dirty_worker = verify_worker(project, created)
assert dirty_worker["ok"] is False and dirty_worker["state"] == "unknown", dirty_worker
subprocess.check_call(["git", "-C", created["worktreePath"], "checkout", "--", "README.md"])
for candidate, merged, confirm in ((created, False, False), (dict(created, owner="host"), True, False)):
    try:
        reclaim(project, candidate, merged=merged, confirm=confirm)
    except LedgerError:
        pass
    else:
        raise AssertionError("unsafe reclaim accepted")
reclaimed = reclaim(project, created, merged=True, confirm=False)
assert reclaimed["ok"] is True and not os.path.lexists(created["worktreePath"]), reclaimed
assert subprocess.run(["git", "-C", project, "show-ref", "--verify", "--quiet", "refs/heads/" + created["branch"]]).returncode != 0
try:
    load_worker_manifest(project, worker)
except LedgerError:
    pass
else:
    raise AssertionError("reclaimed worker manifest remained readable")

run_id = "c" * 64
run = {"schemaVersion": 1, "runId": run_id, "baseSha": head, "goalDigest": "fixture",
       "modules": [{"id": "beta", "rowDigest": "fixture"}]}
assert write_json_exclusive(os.path.join(ledger_root(project), "runs", run_id + ".json"), run)
started = json.loads(subprocess.check_output(["python3", cli, "provision", "--project", project,
                                               "--run", run_id, "--module", "beta", "--format", "json"], text=True))
assert started["ok"] is True and started["manifest"]["moduleId"] == "beta", started
reclaimed_cli = json.loads(subprocess.check_output(["python3", cli, "reclaim", "--project", project,
                                                     "--worker", started["manifest"]["workerId"], "--confirm",
                                                     "--format", "json"], text=True))
assert reclaimed_cli["ok"] is True, reclaimed_cli
with open(worker_manifest_path(project, started["manifest"]["workerId"]), "w", encoding="utf-8") as handle:
    handle.write("{")
corrupt = subprocess.run(["python3", cli, "verify", "--project", project,
                          "--worker", started["manifest"]["workerId"]], stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
assert corrupt.returncode != 0 and "worker manifest" in corrupt.stderr, corrupt.stderr

with open(project + "/README.md", "a", encoding="utf-8") as handle:
    handle.write("dirty\n")
dirty = dict(manifest, workerId="b" * 12 + "-alpha-1")
dirty["worktreePath"] = worker_path(project, dirty["workerId"])
dirty["branch"] = "spec-guard/" + dirty["workerId"]
try:
    provision(project, dirty)
except LedgerError:
    pass
else:
    raise AssertionError("dirty source worktree accepted")
PY

printf 'parallel-worktree-runtime regression passed\n'
