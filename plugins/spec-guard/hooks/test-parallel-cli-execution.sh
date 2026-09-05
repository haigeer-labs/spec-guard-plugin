#!/bin/bash
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
from parallel_cli_adapters import LedgerError, command_for
from parallel_execution_lib import ledger_root
from parallel_worktree_lib import worker_path
from test_parallel_fixture import materialize_worker, write_record

head = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
common = subprocess.check_output(["git", "-C", project, "rev-parse", "--git-common-dir"], text=True).strip()
if not os.path.isabs(common):
    common = os.path.abspath(os.path.join(project, common))
cli = os.path.join(hooks, "parallel-cli.py")
assert command_for("codex-cli", "/absolute/worktree", "codex") == ["codex", "-C", "/absolute/worktree"]
assert command_for("claude-cli", "/absolute/worktree", "claude") == ["claude"]
for host in ("desktop", "unknown"):
    try:
        command_for(host, "/absolute/worktree", "tool")
    except LedgerError:
        pass
    else:
        raise AssertionError("unsupported host accepted")

worker_id = "a" * 12 + "-alpha-1"
manifest = materialize_worker(project, {
    "schemaVersion": 1, "runId": "a" * 64, "workerId": worker_id,
    "moduleId": "alpha", "baseSha": head, "owner": "spec-guard", "gitCommonDir": common,
    "worktreePath": worker_path(project, worker_id), "branch": "spec-guard/" + worker_id,
})
record_path = os.path.join(ledger_root(project), "processes", worker_id + ".json")

def inspect():
    result = subprocess.run([sys.executable, cli, "inspect", "--project", project,
                             "--worker", worker_id, "--format", "json"], capture_output=True, text=True)
    return result, json.loads(result.stdout)

# Legacy records are prepared independently of the disabled process launcher.
for host in ("codex-cli", "claude-cli"):
    for state, exit_code in (("completed", 0), ("failed", 7), ("started", None), ("unknown", None)):
        record = {
            "schemaVersion": 1, "runId": manifest["runId"], "baseSha": head,
            "workerId": worker_id, "moduleId": "alpha", "host": host,
            "worktreePath": manifest["worktreePath"],
            "command": command_for(host, manifest["worktreePath"], host.split("-")[0]),
            "state": state, "startedAt": 0,
        }
        if state != "started":
            record["finishedAt"] = 1
        if exit_code is not None:
            record["returncode"] = exit_code
        if state == "unknown":
            record["reason"] = "旧版进程中断或超时"
        write_record(record_path, record)
        before = open(record_path, "rb").read()
        result, status = inspect()
        assert status["state"] == ("unknown" if state == "started" else state), status
        assert status["ok"] == (state in ("completed", "failed")), status
        assert open(record_path, "rb").read() == before, "inspect changed the process record"
        for _attempt in range(2):
            blocked = subprocess.run([sys.executable, cli, "start", "--project", project,
                                      "--worker", worker_id, "--host", host, "--format", "json"],
                                     capture_output=True, text=True)
            assert blocked.returncode == 1 and blocked.stderr == "", blocked
            assert json.loads(blocked.stdout)["code"] == "PARALLEL_WRITES_DISABLED", blocked.stdout
            assert open(record_path, "rb").read() == before, "start changed an old record"

with open(record_path, "w", encoding="utf-8") as handle:
    handle.write("{")
result, corrupt = inspect()
assert corrupt["ok"] is False and corrupt["state"] == "unknown", corrupt
assert open(record_path, "rb").read() == b"{"
PY

printf 'parallel-cli-execution regression passed\n'
