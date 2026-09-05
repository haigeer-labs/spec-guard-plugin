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

mkdir -p "$WORK/project/spec"
cat > "$WORK/project/spec/CAPABILITY-MAP.md" <<'EOF'
# Capability Map: test

## 目标

验证 run 创建。

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| alpha | A | — |
| beta | B | — |

Build order: alpha → beta
EOF
git -C "$WORK/project" add spec/CAPABILITY-MAP.md
git -C "$WORK/project" commit -qm map
git -C "$WORK/project" remote add origin git@github.com:owner/repo.git

python3 - "$WORK/project" <<'PY'
import json
import subprocess
import sys

project = sys.argv[1]
base = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
for name, sha in (("eligible", base), ("stale", "b" * 40)):
    with open(project + "/" + name + ".json", "w", encoding="utf-8") as handle:
        json.dump({"ok": True, "base": {"sha": sha}, "groups": [{
            "modules": ["alpha", "beta"],
            "classification": "manual-parallel-eligible",
        }]}, handle)
PY

python3 - "$ROOT/hooks/parallel-execution.py" "$WORK/project" <<'PY'
import json
import os
import subprocess
import sys

script, project = sys.argv[1:]
sys.path.insert(0, os.path.dirname(script))
from test_parallel_fixture import write_record
from parallel_execution_lib import ledger_root, run_id

# Build a legacy ledger without calling production write paths: create-run and
# claim-module are intentionally disabled, but status must still inspect their
# old records.
base = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
run = {
    "schemaVersion": 1,
    "runId": run_id("git@github.com:owner/repo.git", base, "fixture", ["alpha", "beta"]),
    "baseSha": base,
    "goalDigest": "fixture",
    "modules": [{"id": "alpha", "rowDigest": "alpha"}, {"id": "beta", "rowDigest": "beta"}],
}
root = ledger_root(project)
write_record(os.path.join(root, "runs", run["runId"] + ".json"), run)
paths = {}
for module_id in ("alpha", "beta"):
    lease_path = os.path.join(root, "leases", run["runId"], "module-" + module_id)
    manifest = {
        "schemaVersion": 1,
        "runId": run["runId"],
        "baseSha": run["baseSha"],
        "moduleId": module_id,
        "workerId": run["runId"][:12] + "-" + module_id + "-1",
        "leasePath": lease_path,
        "owner": "fixture",
        "createdAt": 0,
        "renewedAt": 0,
        "status": "active",
    }
    paths[module_id] = os.path.join(lease_path, "manifest.json")
    write_record(paths[module_id], manifest)

status_command = ["python3", script, "status", "--project", project, "--run", run["runId"], "--format", "json"]
healthy = subprocess.run(status_command, capture_output=True, text=True)
assert healthy.returncode == 0, healthy.stderr
healthy_status = json.loads(healthy.stdout)
assert healthy_status["ok"] is True, healthy_status
assert [item["state"] for item in healthy_status["modules"]] == ["claimed", "claimed"], healthy_status
human_status = subprocess.run(status_command[:-2], capture_output=True, text=True)
assert human_status.returncode == 0 and "alpha: claimed" in human_status.stdout, human_status

alpha_path = paths["alpha"]
with open(alpha_path, encoding="utf-8") as handle:
    expired_manifest = json.load(handle)
expired_manifest["status"] = "expired"
with open(alpha_path, "w", encoding="utf-8") as handle:
    json.dump(expired_manifest, handle)
expired_before = (open(alpha_path, "rb").read(), os.stat(alpha_path).st_mtime_ns)
expired = subprocess.run(status_command, capture_output=True, text=True)
assert expired.returncode == 0, expired.stderr
assert json.loads(expired.stdout)["modules"][0]["state"] == "unknown", expired.stdout
assert (open(alpha_path, "rb").read(), os.stat(alpha_path).st_mtime_ns) == expired_before

beta_path = paths["beta"]
with open(beta_path, "w", encoding="utf-8") as handle:
    handle.write("{")
malformed_before = (open(beta_path, "rb").read(), os.stat(beta_path).st_mtime_ns)
malformed = subprocess.run(status_command, capture_output=True, text=True)
assert malformed.returncode == 0, malformed.stderr
assert json.loads(malformed.stdout)["modules"][1]["state"] == "unknown", malformed.stdout
assert (open(beta_path, "rb").read(), os.stat(beta_path).st_mtime_ns) == malformed_before

os.unlink(alpha_path)
interrupted = subprocess.run(status_command, capture_output=True, text=True)
assert interrupted.returncode == 0, interrupted.stderr
assert json.loads(interrupted.stdout)["modules"][0]["state"] == "unknown", interrupted.stdout
PY

printf 'parallel-execution-ledger regression passed\n'
