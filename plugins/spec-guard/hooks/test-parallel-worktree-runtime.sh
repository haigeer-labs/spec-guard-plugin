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
import os
import subprocess
import sys

hooks, project = sys.argv[1:]
sys.path.insert(0, hooks)

from parallel_worktree_lib import LedgerError, validate_worker_manifest, worker_path  # noqa: F401

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
PY

printf 'parallel-worktree-runtime regression passed\n'
