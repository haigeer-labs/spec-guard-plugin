#!/usr/bin/env python3
"""受控的 Codex / Claude CLI worker argv 派生。"""
from __future__ import print_function

import os

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
