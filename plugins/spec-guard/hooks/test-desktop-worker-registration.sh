#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 - "$ROOT/commands/parallel-register-worker.md" "$ROOT/commands/parallel-status.md" "$ROOT/commands/parallel-reclaim.md" "$ROOT/skills/spec-guard-ops/SKILL.md" "$ROOT/../../README.md" "$ROOT/../../docs/claude-desktop.md" <<'PY'
import sys

register = open(sys.argv[1], encoding="utf-8").read()
for required in ("本次明确确认", "parallel-desktop-register.py\" register", "--host-worker-id", "--cwd",
                 "codex-desktop", "claude-desktop"):
    assert required in register, required
status = open(sys.argv[2], encoding="utf-8").read()
assert "owner=host" in status and "宿主可回收" in status
reclaim = open(sys.argv[3], encoding="utf-8").read()
assert "owner=host" in reclaim and "不得调用" in reclaim
skill = open(sys.argv[4], encoding="utf-8").read()
for required in ("## `parallel-register-worker`", "register-only", "稳定 host worker ID", "不得猜测 ID"):
    assert required in skill, required
readme = open(sys.argv[5], encoding="utf-8").read()
assert "parallel-register-worker" in readme and "仅登记，不创建或回收" in readme
desktop_docs = open(sys.argv[6], encoding="utf-8").read()
for required in ("register-only", "稳定 host worker ID", "不会创建、隐藏、归档或删除", "fail-closed"):
    assert required in desktop_docs, required
PY

git init -q "$WORK/project"
git -C "$WORK/project" config user.email test@example.invalid
git -C "$WORK/project" config user.name test
printf 'fixture\n' > "$WORK/project/README.md"
git -C "$WORK/project" add README.md
git -C "$WORK/project" commit -qm fixture
git -C "$WORK/project" worktree add -q -b desktop-worker "$WORK/desktop-worker"

python3 - "$ROOT/hooks" "$WORK/project" "$WORK/desktop-worker" <<'PY'
import json
import os
import subprocess
import sys

hooks, project, worker = sys.argv[1:]
cli = os.path.join(hooks, "parallel-desktop-register.py")
head = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
run_id = "a" * 64
ledger = os.path.join(project, ".git", "spec-guard", "parallel", "v1")
os.makedirs(os.path.join(ledger, "runs"), exist_ok=True)
with open(os.path.join(ledger, "runs", run_id + ".json"), "w", encoding="utf-8") as handle:
    json.dump({"schemaVersion": 1, "runId": run_id, "baseSha": head, "goalDigest": "fixture",
               "modules": [{"id": "alpha", "rowDigest": "fixture"}]}, handle)

def register(cwd=worker, module="alpha", host_id="codex-thread-123"):
    return subprocess.run(["python3", cli, "register", "--project", project, "--run", run_id,
                           "--module", module, "--host", "codex-desktop", "--host-worker-id", host_id,
                           "--cwd", cwd, "--format", "json"], text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)

success = register()
assert success.returncode == 0, success.stderr
record = json.loads(success.stdout)
manifest = record["manifest"]
assert manifest["owner"] == "host" and manifest["host"] == "codex-desktop", manifest
assert manifest["hostWorkerId"] == "codex-thread-123" and manifest["worktreePath"] == os.path.realpath(worker), manifest
assert manifest["baseSha"] == head and manifest["branch"] == "desktop-worker", manifest
assert not os.path.exists(os.path.join(worker, ".git", "spec-guard")), "registration wrote into Desktop worktree"

for label, arguments in (
    ("duplicate lease", {}),
    ("missing host id", {"host_id": ""}),
    ("main checkout", {"cwd": project}),
    ("wrong module", {"module": "other"}),
):
    result = register(**arguments)
    assert result.returncode != 0, (label, result.stdout, result.stderr)

detached = os.path.join(os.path.dirname(worker), "detached")
subprocess.check_call(["git", "-C", project, "worktree", "add", "--detach", detached, head], stdout=subprocess.DEVNULL)
run_id = "b" * 64
with open(os.path.join(ledger, "runs", run_id + ".json"), "w", encoding="utf-8") as handle:
    json.dump({"schemaVersion": 1, "runId": run_id, "baseSha": head, "goalDigest": "fixture",
               "modules": [{"id": "alpha", "rowDigest": "fixture"}]}, handle)
result = register(cwd=detached, host_id="claude-thread-456")
assert result.returncode != 0 and "detached" in result.stderr, result.stderr

def write_run(identifier):
    global run_id
    run_id = identifier * 64
    with open(os.path.join(ledger, "runs", run_id + ".json"), "w", encoding="utf-8") as handle:
        json.dump({"schemaVersion": 1, "runId": run_id, "baseSha": head, "goalDigest": "fixture",
                   "modules": [{"id": "alpha", "rowDigest": "fixture"}]}, handle)

for label, identifier, arguments, expected in (
    ("missing host id", "c", {"host_id": ""}, "稳定 host worker ID"),
    ("main checkout", "d", {"cwd": project}, "linked worktree"),
    ("wrong module", "e", {"module": "other"}, "module 不属于"),
):
    write_run(identifier)
    result = register(**arguments)
    assert result.returncode != 0 and expected in result.stderr, (label, result.stdout, result.stderr)
PY

printf 'desktop-worker-registration regression passed\n'
