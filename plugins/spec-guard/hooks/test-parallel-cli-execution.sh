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
mkdir -p "$WORK/bin"

cat > "$WORK/bin/codex" <<'EOF'
#!/bin/bash
printf '%s\n' "$PWD" > "$FAKE_CWD"
printf '%s\n' "$*" > "$FAKE_ARGS"
exit "${FAKE_EXIT:-0}"
EOF
chmod +x "$WORK/bin/codex"
ln -s codex "$WORK/bin/claude"

python3 - "$ROOT/hooks" "$WORK/project" "$WORK/bin" "$WORK" <<'PY'
import json
import os
import subprocess
import sys

hooks, project, bin_dir, output_dir = sys.argv[1:]
sys.path.insert(0, hooks)

from parallel_cli_adapters import LedgerError, command_for  # noqa: F401
from parallel_execution_lib import ledger_root, load_json
from parallel_worktree_lib import provision, worker_path

head = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
common = subprocess.check_output(["git", "-C", project, "rev-parse", "--git-common-dir"], text=True).strip()
if not os.path.isabs(common):
    common = os.path.abspath(os.path.join(project, common))
cli = os.path.join(hooks, "parallel-cli.py")

codex = command_for("codex-cli", "/absolute/worktree", "codex")
assert codex == ["codex", "-C", "/absolute/worktree"], codex
claude = command_for("claude-cli", "/absolute/worktree", "claude")
assert claude == ["claude"], claude
for host in ("desktop", "unknown"):
    try:
        command_for(host, "/absolute/worktree", "tool")
    except LedgerError:
        pass
    else:
        raise AssertionError("unsupported host accepted")

def worker(worker_id):
    manifest = {
        "schemaVersion": 1,
        "runId": "a" * 64,
        "workerId": worker_id,
        "moduleId": "alpha",
        "baseSha": head,
        "owner": "spec-guard",
        "gitCommonDir": common,
        "worktreePath": worker_path(project, worker_id),
        "branch": "spec-guard/" + worker_id,
    }
    return provision(project, manifest)

def start(manifest, exit_code, host="codex-cli"):
    env = dict(os.environ, PATH=bin_dir + os.pathsep + os.environ["PATH"],
               FAKE_CWD=os.path.join(output_dir, manifest["workerId"] + ".cwd"),
               FAKE_ARGS=os.path.join(output_dir, manifest["workerId"] + ".args"),
               FAKE_EXIT=str(exit_code))
    raw = subprocess.check_output(["python3", cli, "start",
                                   "--project", project, "--worker", manifest["workerId"],
                                   "--host", host, "--format", "json"], env=env, text=True)
    return json.loads(raw), env

def inspect(worker_id):
    raw = subprocess.check_output(["python3", cli, "inspect", "--project", project,
                                   "--worker", worker_id, "--format", "json"], text=True)
    return json.loads(raw)

completed = worker("a" * 12 + "-alpha-1")
completed_result, completed_env = start(completed, 0)
assert completed_result["state"] == "completed" and completed_result["returncode"] == 0, completed_result
with open(completed_env["FAKE_CWD"], encoding="utf-8") as handle:
    observed_cwd = handle.read().strip()
assert os.path.realpath(observed_cwd) == os.path.realpath(completed["worktreePath"]), (observed_cwd, completed["worktreePath"])
with open(completed_env["FAKE_ARGS"], encoding="utf-8") as handle:
    assert handle.read().strip() == "-C " + completed["worktreePath"]
record = load_json(os.path.join(ledger_root(project), "processes", completed["workerId"] + ".json"), "process record")
assert record["state"] == "completed" and record["command"] == ["codex", "-C", completed["worktreePath"]], record
assert inspect(completed["workerId"])["state"] == "completed"

failed = worker("b" * 12 + "-alpha-1")
failed_result, _ = start(failed, 7)
assert failed_result["state"] == "failed" and failed_result["returncode"] == 7, failed_result
failed_record = load_json(os.path.join(ledger_root(project), "processes", failed["workerId"] + ".json"), "process record")
assert failed_record["state"] == "failed" and failed_record["returncode"] == 7, failed_record
assert inspect(failed["workerId"])["state"] == "failed"

claude = worker("c" * 12 + "-alpha-1")
claude_result, claude_env = start(claude, 0, host="claude-cli")
assert claude_result["state"] == "completed" and claude_result["command"] == ["claude"], claude_result
with open(claude_env["FAKE_CWD"], encoding="utf-8") as handle:
    assert os.path.realpath(handle.read().strip()) == os.path.realpath(claude["worktreePath"])
with open(claude_env["FAKE_ARGS"], encoding="utf-8") as handle:
    assert handle.read().strip() == ""

stuck = worker("d" * 12 + "-alpha-1")
stuck_record = {
    "schemaVersion": 1, "runId": stuck["runId"], "baseSha": stuck["baseSha"],
    "workerId": stuck["workerId"], "moduleId": stuck["moduleId"], "host": "codex-cli",
    "worktreePath": stuck["worktreePath"], "command": ["codex", "-C", stuck["worktreePath"]],
    "state": "started", "startedAt": 0,
}
stuck_path = os.path.join(ledger_root(project), "processes", stuck["workerId"] + ".json")
os.makedirs(os.path.dirname(stuck_path), exist_ok=True)
with open(stuck_path, "w", encoding="utf-8") as handle:
    json.dump(stuck_record, handle)
stuck_status = inspect(stuck["workerId"])
assert stuck_status["ok"] is False and stuck_status["state"] == "unknown", stuck_status

corrupt = worker("e" * 12 + "-alpha-1")
corrupt_path = os.path.join(ledger_root(project), "processes", corrupt["workerId"] + ".json")
with open(corrupt_path, "w", encoding="utf-8") as handle:
    handle.write("{")
corrupt_status = inspect(corrupt["workerId"])
assert corrupt_status["ok"] is False and corrupt_status["state"] == "unknown", corrupt_status
PY

printf 'parallel-cli-execution regression passed\n'
