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
if [ -n "${FAKE_SLEEP:-}" ]; then
  sleep "$FAKE_SLEEP"
fi
exit "${FAKE_EXIT:-0}"
EOF
chmod +x "$WORK/bin/codex"
ln -s codex "$WORK/bin/claude"

python3 - "$ROOT/hooks" "$WORK/project" "$WORK/bin" "$WORK" <<'PY'
import importlib.util
import json
import os
import shutil
import subprocess
import sys

hooks, project, bin_dir, output_dir = sys.argv[1:]
sys.path.insert(0, hooks)

from parallel_cli_adapters import LedgerError, command_for  # noqa: F401
from parallel_execution_lib import ledger_root, load_json
from parallel_worktree_lib import provision, worker_manifest_path, worker_path

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

def start(manifest, exit_code, host="codex-cli", timeout=None, use_fake=True, sleep=None):
    missing_binary_path = os.path.dirname(shutil.which("git"))
    env = dict(os.environ, PATH=(bin_dir + os.pathsep + os.environ["PATH"]) if use_fake else missing_binary_path,
               FAKE_CWD=os.path.join(output_dir, manifest["workerId"] + ".cwd"),
               FAKE_ARGS=os.path.join(output_dir, manifest["workerId"] + ".args"),
               FAKE_EXIT=str(exit_code))
    if sleep is not None:
        env["FAKE_SLEEP"] = str(sleep)
    arguments = [sys.executable, cli, "start",
                                   "--project", project, "--worker", manifest["workerId"],
                                   "--host", host]
    if timeout is not None:
        arguments.extend(["--timeout-seconds", str(timeout)])
    arguments.extend(["--format", "json"])
    raw = subprocess.check_output(arguments, env=env, text=True)
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

timed_out = worker("f" * 12 + "-alpha-1")
timed_out_result, _ = start(timed_out, 0, timeout=0.01, sleep=1)
assert timed_out_result["state"] == "unknown" and "超时" in timed_out_result["reason"], timed_out_result
assert inspect(timed_out["workerId"])["state"] == "unknown"

missing = worker("a" * 12 + "-alpha-2")
missing_result, _ = start(missing, 0, use_fake=False)
assert missing_result["state"] == "unknown" and "未找到 codex CLI" in missing_result["reason"], missing_result

module_spec = importlib.util.spec_from_file_location("parallel_cli_test", cli)
parallel_cli = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(parallel_cli)
interrupted = worker("b" * 12 + "-alpha-2")
original_run_worker = parallel_cli.run_worker
try:
    def interrupt(*_args, **_kwargs):
        raise KeyboardInterrupt
    parallel_cli.run_worker = interrupt
    interrupted_result = parallel_cli.start_worker(project, interrupted["workerId"], "codex-cli")
finally:
    parallel_cli.run_worker = original_run_worker
assert interrupted_result["state"] == "unknown" and "中断" in interrupted_result["reason"], interrupted_result

tampered = worker("c" * 12 + "-alpha-2")
manifest_path = worker_manifest_path(project, tampered["workerId"])
with open(manifest_path, encoding="utf-8") as handle:
    tampered_manifest = json.load(handle)
tampered_manifest["branch"] = "other-branch"
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(tampered_manifest, handle)
tampered_start = subprocess.run([sys.executable, cli, "start", "--project", project,
                                 "--worker", tampered["workerId"], "--host", "codex-cli"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
assert tampered_start.returncode == 1 and "worker branch" in tampered_start.stderr, tampered_start.stderr

# 已创建但尚未启动的 worker 不得在 controller 初始基线漂移后启动。
drifted = worker("d" * 12 + "-alpha-2")
with open(os.path.join(project, "README.md"), "a", encoding="utf-8") as handle:
    handle.write("controller advanced\n")
subprocess.check_call(["git", "-C", project, "add", "README.md"])
subprocess.check_call(["git", "-C", project, "commit", "-qm", "controller advanced"])
try:
    parallel_cli.start_worker(project, drifted["workerId"], "codex-cli")
except LedgerError as error:
    assert "基线" in str(error), error
else:
    raise AssertionError("baseline-drifted worker start accepted")
PY

printf 'parallel-cli-execution regression passed\n'
