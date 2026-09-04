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
command = ["python3", script, "create-run", "--project", project, "--safety-report", project + "/eligible.json", "--format", "json"]
first = subprocess.run(command, capture_output=True, text=True)
assert first.returncode == 0, first.stderr
created = json.loads(first.stdout)
assert created["created"] is True, created
run = created["run"]
assert run["baseSha"] == subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
assert [module["id"] for module in run["modules"]] == ["alpha", "beta"], run
assert os.path.isfile(created["path"]), created

second = subprocess.run(command, capture_output=True, text=True)
assert second.returncode == 0, second.stderr
again = json.loads(second.stdout)
assert again["created"] is False and again["run"]["runId"] == run["runId"], again

stale_command = command[:]
stale_command[stale_command.index(project + "/eligible.json")] = project + "/stale.json"
stale = subprocess.run(stale_command, capture_output=True, text=True)
assert stale.returncode != 0 and "base SHA" in stale.stderr, stale.stderr
PY

printf 'parallel-execution-ledger regression passed\n'
