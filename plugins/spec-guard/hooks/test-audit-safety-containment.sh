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
import re
import subprocess
import sys
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor

hooks, project = sys.argv[1:]
sys.path.insert(0, hooks)

from parallel_execution_lib import (ParallelWritesDisabled, claim_lease, ledger_root,
                                    run_id)
import parallel_worktree_lib
from test_parallel_fixture import materialize_worker, write_record
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

import parallel_cli_adapters
cli_spec = importlib.util.spec_from_file_location("parallel_cli_test", os.path.join(hooks, "parallel-cli.py"))
parallel_cli = importlib.util.module_from_spec(cli_spec)
cli_spec.loader.exec_module(parallel_cli)
for host in ("codex-cli", "claude-cli"):
    for action in (
            lambda: parallel_cli.start_worker(project, worker_id, host),
            lambda: parallel_cli_adapters.run_worker(host, worker["worktreePath"])):
        before = snapshot()
        with patch.object(parallel_cli, "load_worker_manifest", side_effect=AssertionError("manifest read reached")), \
                patch.object(parallel_cli_adapters.shutil, "which", side_effect=AssertionError("CLI discovery reached")), \
                patch.object(parallel_cli_adapters.subprocess, "run", side_effect=AssertionError("process launch reached")):
            try:
                action()
            except ParallelWritesDisabled:
                pass
            else:
                raise AssertionError("CLI launch was not disabled")
        assert snapshot() == before, "disabled CLI launch wrote a process record"
    for target in (project, project + "-missing"):
        result = subprocess.run([sys.executable, os.path.join(hooks, "parallel-cli.py"),
                                 "start", "--project", target, "--worker", worker_id,
                                 "--host", host, "--format", "json"], capture_output=True, text=True)
        assert result.returncode == 1 and result.stderr == "", result
        assert json.loads(result.stdout)["code"] == "PARALLEL_WRITES_DISABLED", result.stdout
        assert snapshot() == before

desktop_spec = importlib.util.spec_from_file_location("parallel_desktop_test", os.path.join(hooks, "parallel-desktop-register.py"))
desktop = importlib.util.module_from_spec(desktop_spec)
desktop_spec.loader.exec_module(desktop)
before = snapshot()
for host in ("codex-desktop", "claude-desktop"):
    with patch.object(desktop, "_git", side_effect=AssertionError("Desktop Git lookup reached")):
        try:
            desktop.register(project, "c" * 64, "beta", host, "existing-task", worker["worktreePath"])
        except ParallelWritesDisabled:
            pass
        else:
            raise AssertionError("Desktop registration was not disabled")

def register_request(args):
    host, run_value, module = args
    return subprocess.run([sys.executable, os.path.join(hooks, "parallel-desktop-register.py"),
                           "register", "--project", project, "--run", run_value,
                           "--module", module, "--host", host, "--host-worker-id", "existing-task",
                           "--cwd", worker["worktreePath"], "--format", "json"],
                          capture_output=True, text=True)

requests = [(host, value * 64, module) for host in ("codex-desktop", "claude-desktop")
            for value in ("c", "d") for module in ("alpha", "beta")]
with ThreadPoolExecutor(max_workers=4) as executor:
    for result in executor.map(register_request, requests):
        assert result.returncode == 1 and result.stderr == "", result
        assert json.loads(result.stdout)["code"] == "PARALLEL_WRITES_DISABLED", result.stdout
assert snapshot() == before, "concurrent Desktop registration changed old resources"

# Read-only status must reject foreign identities and symlinks without reading the target.
run_path = os.path.join(root, "runs", run["runId"] + ".json")
write_record(run_path, run)
assert parallel_execution.status_run(project, run["runId"])["ok"] is True
for invalid in ("../outside", run["runId"] + "\n"):
    assert parallel_execution.status_run(project, invalid)["ok"] is False
write_record(run_path, dict(run, runId="e" * 64))
assert parallel_execution.status_run(project, run["runId"])["ok"] is False
write_record(run_path, run)
canary = os.path.join(os.path.dirname(project), "external-canary.json")
write_record(canary, run)
canary_inode = os.stat(canary).st_ino
original_json_load = json.load
def checked_json_load(handle, *args, **kwargs):
    assert os.fstat(handle.fileno()).st_ino != canary_inode, "external canary was read"
    return original_json_load(handle, *args, **kwargs)
os.unlink(run_path)
os.symlink(canary, run_path)
with patch.object(json, "load", checked_json_load):
    assert parallel_execution.status_run(project, run["runId"])["ok"] is False
os.unlink(run_path)
write_record(run_path, run)
runs_dir = os.path.dirname(run_path)
os.rename(runs_dir, runs_dir + "-saved")
os.symlink(runs_dir + "-saved", runs_dir)
assert parallel_execution.status_run(project, run["runId"])["ok"] is False
os.unlink(runs_dir)
os.rename(runs_dir + "-saved", runs_dir)
before = snapshot()
missing = parallel_execution.status_run(project, "f" * 64)
assert missing["ok"] is False and snapshot() == before

# Missing resources, swapped worker IDs and process symlinks are observable failures.
worker_file = parallel_worktree_lib.worker_manifest_path(project, worker_id)
write_record(worker_file, dict(worker, workerId="e" * 12 + "-beta-1"))
try:
    parallel_worktree_lib.load_worker_manifest(project, worker_id)
except parallel_worktree_lib.LedgerError:
    pass
else:
    raise AssertionError("swapped worker identity was accepted")
write_record(worker_file, worker)
os.rename(worker["worktreePath"], worker["worktreePath"] + "-saved")
assert parallel_execution.status_run(project, worker["runId"])["ok"] is False
os.rename(worker["worktreePath"] + "-saved", worker["worktreePath"])
process_path = os.path.join(root, "processes", worker_id + ".json")
os.makedirs(os.path.dirname(process_path), exist_ok=True)
os.symlink(canary, process_path)
with patch.object(json, "load", checked_json_load):
    assert parallel_cli.inspect_worker(project, worker_id)["ok"] is False
os.unlink(process_path)

# Host-owned workers have their own identity and no controller process record.
for host in ("codex-desktop", "claude-desktop"):
    host_worker = dict(worker, owner="host", host=host, hostWorkerId="native-task-id")
    write_record(worker_file, host_worker)
    before = snapshot()
    status = parallel_cli.inspect_worker(project, worker_id)
    assert status["ok"] is True and status["state"] == "unverified", status
    assert status["owner"] == "host" and "未核验" in status["reason"], status
    assert snapshot() == before and not os.path.exists(process_path)
write_record(worker_file, worker)

# Execute the exact Claude command and Codex ops snippets against the same ledger.
plugin_root = os.path.dirname(hooks)
command = open(os.path.join(plugin_root, "commands", "parallel-status.md"), encoding="utf-8").read()
ops = open(os.path.join(plugin_root, "skills", "spec-guard-ops", "SKILL.md"), encoding="utf-8").read()
status_section = ops.split("## `parallel-status`", 1)[1].split("\n## `", 1)[0]
blocks = [re.findall(r"```bash\n(.*?)\n```", text, re.S)[0] for text in (command, status_section)]
env = dict(os.environ, ROOT=plugin_root, PROJECT=project, RUN=worker["runId"],
           CLAUDE_PLUGIN_ROOT=plugin_root, CLAUDE_PROJECT_DIR=project, ARGUMENTS=worker["runId"],
           PYTHONDONTWRITEBYTECODE="1")
for owner in ("spec-guard", "host"):
    write_record(worker_file, dict(worker, owner=owner, host="codex-desktop", hostWorkerId="native-task"))
    before = snapshot()
    results = [subprocess.run(["/bin/bash", "-c", block], env=env, capture_output=True, text=True) for block in blocks]
    payloads = [json.loads(result.stdout) for result in results]
    assert payloads[0] == payloads[1], payloads
    for result, payload in zip(results, payloads):
        assert result.returncode == (0 if owner == "host" else 1), result
        assert payload["ok"] == (owner == "host"), payload
        assert len(payload["workers"]) == 1, payload
        if owner == "host":
            assert "process" not in payload["workers"][0], payload
            assert payload["workers"][0]["runtime"]["state"] == "unverified", payload
    assert snapshot() == before, "status command modified resources"
write_record(worker_file, worker)
PY

printf 'audit-safety-containment regression passed\n'
