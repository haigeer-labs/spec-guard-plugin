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
git -C "$WORK/project" worktree add -q -b desktop-worker "$WORK/desktop-worker"

python3 - "$ROOT" "$WORK/project" "$WORK/desktop-worker" <<'PY'
import json
import os
import subprocess
import sys

root, project, worker = sys.argv[1:]
for path in ("commands/parallel-register-worker.md", "skills/spec-guard-ops/SKILL.md", "../../README.md"):
    text = open(os.path.join(root, path), encoding="utf-8").read()
    assert "PARALLEL_WRITES_DISABLED" in text, path
desktop = open(os.path.join(root, "../../docs/claude-desktop.md"), encoding="utf-8").read()
for token in ("已暂停", "完成与可回收性未核验", "升级不会停止旧进程", "尚未发布"):
    assert token in desktop, token
assert "宿主可回收" not in desktop

def snapshot():
    files = {}
    for base, _dirs, names in os.walk(os.path.dirname(project)):
        for name in names:
            path = os.path.join(base, name)
            files[path] = open(path, "rb").read()
    return files

before = snapshot()
for host in ("codex-desktop", "claude-desktop"):
    for cwd, module, host_id in ((worker, "alpha", "native-task-id"),
                                 (worker, "beta", "native-task-id"),
                                 (worker, "alpha", ""),
                                 (project, "alpha", "native-task-id"),
                                 (worker + "-missing", "other", "native-task-id")):
        result = subprocess.run([sys.executable, os.path.join(root, "hooks/parallel-desktop-register.py"),
                                 "register", "--project", project, "--run", "a" * 64, "--module", module,
                                 "--host", host, "--host-worker-id", host_id, "--cwd", cwd, "--format", "json"],
                                capture_output=True, text=True, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
        assert result.returncode == 1 and result.stderr == "", result
        assert json.loads(result.stdout)["code"] == "PARALLEL_WRITES_DISABLED", result.stdout
        assert snapshot() == before, "registration changed native worktree or Git metadata"
PY
printf 'desktop-worker-registration regression passed\n'
