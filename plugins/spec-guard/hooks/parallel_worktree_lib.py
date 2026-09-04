#!/usr/bin/env python3
"""Spec Guard controller-owned linked worktree 的身份与路径校验。"""
from __future__ import print_function

import os
import re

from parallel_execution_lib import LedgerError, current_head, ledger_root, validate_module_id, validate_record


WORKER_ID = re.compile(r"^[0-9a-f]{12}-[a-z0-9]+(?:-[a-z0-9]+)*-[1-9][0-9]*$")


def worker_path(project, worker_id):
    """返回只属于本 controller 的 worktree 位置，不接受调用方提供的目录。"""
    if not isinstance(worker_id, str) or not WORKER_ID.match(worker_id):
        raise LedgerError("workerId 无效")
    return os.path.join(ledger_root(project), "worktrees", worker_id)


def _common_dir(project):
    root = ledger_root(project)
    return os.path.dirname(os.path.dirname(os.path.dirname(root)))


def validate_worker_manifest(project, manifest):
    """验证 controller-owned worker 的不可变 Git 身份，失败时绝不降级。"""
    validate_record(manifest, ("schemaVersion", "runId", "workerId", "moduleId", "baseSha",
                               "owner", "gitCommonDir", "worktreePath", "branch"))
    validate_module_id(manifest["moduleId"])
    worker_id = manifest["workerId"]
    expected_path = worker_path(project, worker_id)
    if manifest["owner"] != "spec-guard":
        raise LedgerError("worker owner 不属于 spec-guard")
    if not isinstance(manifest["gitCommonDir"], str) or os.path.abspath(manifest["gitCommonDir"]) != _common_dir(project):
        raise LedgerError("worker git common-dir 不匹配")
    if not isinstance(manifest["worktreePath"], str) or os.path.abspath(manifest["worktreePath"]) != expected_path:
        raise LedgerError("worker worktree 路径不属于 controller")
    if manifest["baseSha"] != current_head(project):
        raise LedgerError("worker 基线与当前 HEAD 不一致")
    if manifest["branch"] != "spec-guard/" + worker_id:
        raise LedgerError("worker branch 不匹配")
    return manifest
