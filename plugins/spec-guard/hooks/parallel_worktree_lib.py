#!/usr/bin/env python3
"""Spec Guard controller-owned linked worktree 的身份与路径校验。"""
from __future__ import print_function

import os
import re
import subprocess

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


def _git(project, *args):
    result = subprocess.run(["git", "-C", project] + list(args), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise LedgerError(detail or "git 命令失败")
    return result.stdout.strip()


def provision(project, manifest):
    """创建 controller-owned linked worktree；失败时不返回可启动 worker。"""
    project = os.path.abspath(project)
    manifest = validate_worker_manifest(project, manifest)
    if _git(project, "status", "--porcelain"):
        raise LedgerError("源 worktree 不干净")
    target = manifest["worktreePath"]
    if os.path.lexists(target):
        raise LedgerError("worker worktree 已存在")
    if subprocess.run(["git", "-C", project, "show-ref", "--verify", "--quiet",
                       "refs/heads/" + manifest["branch"]]).returncode == 0:
        raise LedgerError("worker branch 已存在")
    try:
        _git(project, "worktree", "add", "-b", manifest["branch"], target, manifest["baseSha"])
        if _git(target, "rev-parse", "HEAD") != manifest["baseSha"] or _git(target, "branch", "--show-current") != manifest["branch"]:
            raise LedgerError("新 worktree Git 元数据不匹配")
    except LedgerError:
        raise
    return manifest


def verify_worker(project, manifest):
    """只读验证已创建的 worker；任何无法证明的状态均阻断启动。"""
    try:
        project = os.path.abspath(project)
        manifest = validate_worker_manifest(project, manifest)
        target = manifest["worktreePath"]
        if not os.path.isdir(target):
            raise LedgerError("worker worktree 不存在")
        common = _git(target, "rev-parse", "--git-common-dir")
        if not os.path.isabs(common):
            common = os.path.abspath(os.path.join(target, common))
        if os.path.realpath(common) != os.path.realpath(manifest["gitCommonDir"]):
            raise LedgerError("worker worktree common-dir 不匹配")
        if _git(target, "rev-parse", "HEAD") != manifest["baseSha"]:
            raise LedgerError("worker worktree HEAD 不匹配")
        if _git(target, "branch", "--show-current") != manifest["branch"]:
            raise LedgerError("worker worktree branch 不匹配")
        if _git(target, "status", "--porcelain"):
            raise LedgerError("worker worktree 不干净")
    except LedgerError as error:
        return {"ok": False, "state": "unknown", "reason": str(error)}
    return {"ok": True, "state": "ready", "workerId": manifest["workerId"],
            "worktreePath": manifest["worktreePath"]}


def reclaim(project, manifest, merged=False, confirm=False):
    """只回收已合并或明确 discard 的 controller-owned 干净 worker。"""
    project = os.path.abspath(project)
    manifest = validate_worker_manifest(project, manifest)
    if not merged and not confirm:
        raise LedgerError("未合并 worker 必须显式 confirm discard")
    status = verify_worker(project, manifest)
    if status["ok"] is not True:
        raise LedgerError("worker 不可安全回收: %s" % status["reason"])
    _git(project, "worktree", "remove", manifest["worktreePath"])
    _git(project, "branch", "-d" if merged else "-D", manifest["branch"])
    _git(project, "worktree", "prune")
    return {"ok": True, "workerId": manifest["workerId"], "state": "reclaimed"}
