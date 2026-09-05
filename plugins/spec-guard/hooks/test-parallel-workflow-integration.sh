#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import json
import os
import re
import subprocess
import sys
import tempfile

root = sys.argv[1]
for name in ("parallel-execute", "parallel-integrate", "parallel-reclaim", "parallel-register-worker"):
    text = open(os.path.join(root, "commands", name + ".md"), encoding="utf-8").read()
    blocks = re.findall(r"```bash\n(.*?)\n```", text, re.S)
    assert len(blocks) == 1, (name, len(blocks))
    assert "PARALLEL_WRITES_DISABLED" in text and "/spec-guard:parallel-status" in text
    with tempfile.TemporaryDirectory() as project:
        before = os.listdir(project)
        env = dict(os.environ, CLAUDE_PLUGIN_ROOT=root, CLAUDE_PROJECT_DIR=project,
                   ARGUMENTS="legacy-run legacy-worker --confirm --merged",
                   PYTHONDONTWRITEBYTECODE="1")
        result = subprocess.run(["/bin/bash", "-c", blocks[0]], cwd=project, env=env,
                                capture_output=True, text=True)
        assert result.returncode == 1 and result.stderr == "", (name, result)
        assert json.loads(result.stdout)["code"] == "PARALLEL_WRITES_DISABLED", result.stdout
        assert os.listdir(project) == before, (name, "command wrote project files")
    for forbidden in ("merge --no-ff", "worktree remove", "branch -D", "create-run", " provision", "register \\"):
        assert forbidden not in text, (name, forbidden)

for name in ("next.md", "deliver.md"):
    command = open(os.path.join(root, "commands", name), encoding="utf-8").read()
    for required in ("spec-guard/<worker-id>", "parallel-worktree.py verify", "moduleId",
                     "不得继续执行下面的 canonical", "activeModule"):
        assert required in command, (name, required)

status = open(os.path.join(root, "commands", "parallel-status.md"), encoding="utf-8").read()
assert "这是只读命令" in status
assert "--details --format json" in status and "recordedState" in status
assert "|| true" not in status and "宿主可回收" not in status
for forbidden in (" create-run", " provision", " reclaim", '" start'):
    assert forbidden not in status, forbidden
readme = open(os.path.join(root, "../../README.md"), encoding="utf-8").read()
for token in ("实验性写操作已暂停", "尚未发布", "新代码不会停止旧进程", "查询成功仅表示读取成功"):
    assert token in readme, token
PY

printf 'parallel-workflow-integration regression passed\n'
