#!/usr/bin/env python3
"""受控的 Codex / Claude CLI worker argv 派生。"""
from __future__ import print_function

import os
import shutil
import subprocess

from parallel_execution_lib import LedgerError


def command_for(host, worktree_path, executable):
    if host not in ("codex-cli", "claude-cli"):
        raise LedgerError("不支持的 CLI host")
    if not isinstance(executable, str) or not executable or os.path.sep in executable:
        raise LedgerError("CLI executable 无效")
    if not isinstance(worktree_path, str) or not os.path.isabs(worktree_path):
        raise LedgerError("worker worktree 路径必须是绝对路径")
    if host == "codex-cli":
        return [executable, "-C", worktree_path]
    return [executable]


def run_worker(host, worktree_path):
    """在已验证的 worktree 中同步运行固定的宿主 CLI。"""
    executable = {"codex-cli": "codex", "claude-cli": "claude"}.get(host)
    if executable is None:
        raise LedgerError("不支持的 CLI host")
    if shutil.which(executable) is None:
        raise LedgerError("未找到 %s CLI" % executable)
    command = command_for(host, worktree_path, executable)
    try:
        result = subprocess.run(command, cwd=worktree_path, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, check=False)
    except OSError as error:
        raise LedgerError("无法启动 %s: %s" % (executable, error))
    return {"command": command, "returncode": result.returncode,
            "state": "completed" if result.returncode == 0 else "failed"}
