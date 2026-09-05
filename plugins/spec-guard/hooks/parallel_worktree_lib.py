#!/usr/bin/env python3
"""Spec Guard controller-owned linked worktree 的身份与路径校验。"""
from __future__ import print_function

import os
import re
import subprocess

from parallel_execution_lib import (LedgerError, current_head, ledger_root, load_json,
                                    reject_parallel_write, validate_module_id, validate_record,
                                    write_json_exclusive, load_ledger_json, load_run, validate_worker_link)


WORKER_ID = re.compile(r"^[0-9a-f]{12}-[a-z0-9]+(?:-[a-z0-9]+)*-[1-9][0-9]*$")


def worker_path(project, worker_id):
    """返回只属于本 controller 的 worktree 位置，不接受调用方提供的目录。"""
    if not isinstance(worker_id, str) or not WORKER_ID.fullmatch(worker_id):
        raise LedgerError("workerId 无效")
    return os.path.join(ledger_root(project), "worktrees", worker_id)


def worker_manifest_path(project, worker_id):
    """返回 controller-owned worker manifest 的唯一账本位置。"""
    worker_path(project, worker_id)
    return os.path.join(ledger_root(project), "workers", worker_id + ".json")


def load_worker_manifest(project, worker_id):
    """按 worker ID 读取完整 provenance；缺失或损坏均不可启动。"""
    worker_manifest_path(project, worker_id)
    root = ledger_root(project)
    manifest = load_ledger_json(root, "workers", worker_id + ".json")
    validate_worker_manifest(project, manifest)
    run = load_run(root, manifest["runId"])
    validate_worker_link(run, manifest, worker_id, manifest["moduleId"])
    lease = load_ledger_json(root, "leases", run["runId"], "module-" + manifest["moduleId"], "manifest.json")
    validate_worker_link(run, lease, worker_id, manifest["moduleId"])
    return manifest


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
    if manifest["owner"] == "host":
        if (manifest.get("host") not in ("codex-desktop", "claude-desktop") or
                not isinstance(manifest.get("hostWorkerId"), str) or not manifest["hostWorkerId"] or
                not isinstance(manifest["worktreePath"], str) or not os.path.isabs(manifest["worktreePath"]) or
                not isinstance(manifest["branch"], str) or not manifest["branch"] or
                not isinstance(manifest["gitCommonDir"], str) or
                os.path.realpath(manifest["gitCommonDir"]) != os.path.realpath(_common_dir(project))):
            raise LedgerError("host worker 身份无法核验")
        return manifest
    if manifest["owner"] != "spec-guard":
        raise LedgerError("worker owner 不属于 spec-guard")
    if not isinstance(manifest["gitCommonDir"], str) or os.path.abspath(manifest["gitCommonDir"]) != _common_dir(project):
        raise LedgerError("worker git common-dir 不匹配")
    if not isinstance(manifest["worktreePath"], str) or os.path.abspath(manifest["worktreePath"]) != expected_path:
        raise LedgerError("worker worktree 路径不属于 controller")
    if manifest["branch"] != "spec-guard/" + worker_id:
        raise LedgerError("worker branch 不匹配")
    return manifest


def _require_initial_base(project, manifest):
    if manifest["baseSha"] != current_head(project):
        raise LedgerError("worker 基线与当前 HEAD 不一致")


def _git(project, *args):
    result = subprocess.run(["git", "-C", project] + list(args), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"))
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise LedgerError(detail or "git 命令失败")
    return result.stdout.strip()


def provision(project, manifest):
    """创建 controller-owned linked worktree；失败时不返回可启动 worker。"""
    reject_parallel_write()
    project = os.path.abspath(project)
    manifest = validate_worker_manifest(project, manifest)
    _require_initial_base(project, manifest)
    if _git(project, "status", "--porcelain"):
        raise LedgerError("源 worktree 不干净")
    target = manifest["worktreePath"]
    manifest_path = worker_manifest_path(project, manifest["workerId"])
    if os.path.lexists(target):
        raise LedgerError("worker worktree 已存在")
    if os.path.lexists(manifest_path):
        raise LedgerError("worker manifest 已存在")
    if subprocess.run(["git", "-C", project, "show-ref", "--verify", "--quiet",
                       "refs/heads/" + manifest["branch"]]).returncode == 0:
        raise LedgerError("worker branch 已存在")
    created = False
    try:
        _git(project, "worktree", "add", "-b", manifest["branch"], target, manifest["baseSha"])
        created = True
        if _git(target, "rev-parse", "HEAD") != manifest["baseSha"] or _git(target, "branch", "--show-current") != manifest["branch"]:
            raise LedgerError("新 worktree Git 元数据不匹配")
        if not write_json_exclusive(manifest_path, manifest):
            raise LedgerError("worker manifest 已存在")
    except LedgerError:
        if created:
            subprocess.run(["git", "-C", project, "worktree", "remove", "--force", target],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            subprocess.run(["git", "-C", project, "branch", "-D", manifest["branch"]],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        raise
    return manifest


def verify_worker(project, manifest):
    """只读验证已创建的 worker；任何无法证明的状态均阻断启动。"""
    try:
        project = os.path.abspath(project)
        manifest = validate_worker_manifest(project, manifest)
        if load_worker_manifest(project, manifest["workerId"]) != manifest:
            raise LedgerError("worker manifest 与账本不匹配")
        target = manifest["worktreePath"]
        if not os.path.isdir(target):
            raise LedgerError("worker worktree 不存在")
        common = _git(target, "rev-parse", "--git-common-dir")
        if not os.path.isabs(common):
            common = os.path.abspath(os.path.join(target, common))
        if os.path.realpath(common) != os.path.realpath(manifest["gitCommonDir"]):
            raise LedgerError("worker worktree common-dir 不匹配")
        if manifest["owner"] == "host":
            git_dir = _git(target, "rev-parse", "--absolute-git-dir")
            if os.path.realpath(git_dir) == os.path.realpath(common):
                raise LedgerError("host worker 不是 linked worktree")
        worker_head = _git(target, "rev-parse", "HEAD")
        if subprocess.run(["git", "-C", target, "merge-base", "--is-ancestor",
                           manifest["baseSha"], worker_head]).returncode != 0:
            raise LedgerError("worker worktree HEAD 未从初始 base 演进")
        if _git(target, "branch", "--show-current") != manifest["branch"]:
            raise LedgerError("worker worktree branch 不匹配")
        if _git(target, "status", "--porcelain"):
            raise LedgerError("worker worktree 不干净")
    except (LedgerError, OSError, ValueError, KeyError) as error:
        return {"ok": False, "state": "unknown", "reason": str(error)}
    if manifest["owner"] == "host":
        return {"ok": True, "state": "unverified", "owner": "host", "workerId": manifest["workerId"],
                "host": manifest["host"], "hostWorkerId": manifest["hostWorkerId"],
                "worktreePath": target, "branch": manifest["branch"],
                "reason": "宿主管理；完成与可回收性未核验"}
    return {"ok": True, "state": "ready", "workerId": manifest["workerId"],
            "worktreePath": manifest["worktreePath"], "workerHead": worker_head}


def reclaim(project, manifest, merged=False, confirm=False):
    """只回收已合并或明确 discard 的 controller-owned 干净 worker。"""
    reject_parallel_write()
    project = os.path.abspath(project)
    manifest = validate_worker_manifest(project, manifest)
    if not merged and not confirm:
        raise LedgerError("未合并 worker 必须显式 confirm discard")
    if load_worker_manifest(project, manifest["workerId"]) != manifest:
        raise LedgerError("worker manifest 与账本不匹配")
    status = verify_worker(project, manifest)
    if status["ok"] is not True:
        raise LedgerError("worker 不可安全回收: %s" % status["reason"])
    if merged and subprocess.run(["git", "-C", project, "merge-base", "--is-ancestor",
                                  manifest["branch"], current_head(project)]).returncode != 0:
        raise LedgerError("worker branch 尚未汇合到当前 HEAD")
    _git(project, "worktree", "remove", manifest["worktreePath"])
    _git(project, "branch", "-d" if merged else "-D", manifest["branch"])
    _git(project, "worktree", "prune")
    try:
        os.unlink(worker_manifest_path(project, manifest["workerId"]))
    except OSError as error:
        raise LedgerError("无法删除 worker manifest: %s" % error)
    return {"ok": True, "workerId": manifest["workerId"], "state": "reclaimed"}
