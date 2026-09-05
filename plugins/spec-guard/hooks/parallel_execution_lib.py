#!/usr/bin/env python3
"""Worktree 并行执行账本的身份、路径和记录校验基元。"""
from __future__ import print_function

import getpass
import hashlib
import json
import os
import re
import subprocess
import stat
import time


SCHEMA_VERSION = 1
MODULE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SHA40 = re.compile(r"^[0-9a-f]{40}$")
RUN_ID = re.compile(r"^[0-9a-f]{64}$")


class LedgerError(Exception):
    """账本输入或本地 Git 身份无法安全验证。"""


class ParallelWritesDisabled(LedgerError):
    """实验性并行写入已暂停，调用方不得尝试绕过。"""

    code = "PARALLEL_WRITES_DISABLED"


def reject_parallel_write():
    raise ParallelWritesDisabled("实验性并行写操作已暂停；已有成果保留，请使用只读状态检查。")


class ClaimConflict(LedgerError):
    """另一个 worker 已原子领取相同模块。"""


def _git(project, *args):
    result = subprocess.run(
        ["git", "-C", project] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise LedgerError(detail or "git 命令失败")
    return result.stdout.strip()


def ledger_root(project):
    """返回同一 clone 的全部 linked worktree 共用的版本化账本目录。"""
    absolute_project = os.path.abspath(project)
    common_dir = _git(absolute_project, "rev-parse", "--git-common-dir")
    if not os.path.isabs(common_dir):
        common_dir = os.path.abspath(os.path.join(absolute_project, common_dir))
    return os.path.join(common_dir, "spec-guard", "parallel", "v%d" % SCHEMA_VERSION)


def _normalize_remote(remote):
    value = remote.strip()
    if value.startswith("git@") and ":" in value:
        host, path = value[4:].split(":", 1)
        value = "%s/%s" % (host, path)
    else:
        value = re.sub(r"^[a-z][a-z0-9+.-]*://", "", value, flags=re.I)
        value = value.split("@", 1)[-1]
    value = value.rstrip("/")
    if value.endswith(".git"):
        value = value[:-4]
    if not value or "/" not in value or ".." in value.split("/"):
        raise LedgerError("remote 不是可规范化的仓库地址")
    return value.lower()


def run_id(remote, base_sha, goal_digest, module_digests):
    """计算可安全重试的 run 身份；它描述意图而非某次执行尝试。"""
    if not SHA40.match(base_sha):
        raise LedgerError("base SHA 必须是完整的 40 位小写十六进制值")
    if not isinstance(goal_digest, str) or not goal_digest:
        raise LedgerError("goal digest 缺失")
    if not isinstance(module_digests, (list, tuple)) or not module_digests:
        raise LedgerError("module digests 必须是非空有序列表")
    if any(not isinstance(value, str) or not value for value in module_digests):
        raise LedgerError("module digest 无效")
    payload = "\n".join([
        _normalize_remote(remote), base_sha, goal_digest,
    ] + list(module_digests))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def validate_module_id(module_id):
    if not isinstance(module_id, str) or not MODULE_ID.fullmatch(module_id):
        raise LedgerError("module id 必须是 kebab-case")


def validate_run_id(value):
    if not isinstance(value, str) or not RUN_ID.fullmatch(value):
        raise LedgerError("runId 无效")


def validate_record(record, required_fields):
    """验证所有 ledger JSON 记录共享的最小不可变字段。"""
    if not isinstance(record, dict):
        raise LedgerError("账本记录必须是对象")
    if type(record.get("schemaVersion")) is not int or record["schemaVersion"] != SCHEMA_VERSION:
        raise LedgerError("不支持的账本 schema version")
    for field in required_fields:
        if field not in record:
            raise LedgerError("账本记录缺少字段: %s" % field)
    validate_run_id(record.get("runId"))
    if not isinstance(record.get("baseSha"), str) or not SHA40.match(record["baseSha"]):
        raise LedgerError("base SHA 无效")


def current_head(project):
    head = _git(os.path.abspath(project), "rev-parse", "HEAD")
    if not SHA40.match(head):
        raise LedgerError("当前 HEAD 不是完整 commit SHA")
    return head


def origin_remote(project):
    return _git(os.path.abspath(project), "remote", "get-url", "origin")


def load_json(path, label):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as error:
        raise LedgerError("%s 无法读取: %s" % (label, error))


def load_ledger_json(root, *parts):
    """Read regular ledger files without following symlinks, including parent directories."""
    if os.open not in os.supports_dir_fd or not all(hasattr(os, flag) for flag in ("O_DIRECTORY", "O_NOFOLLOW", "O_NONBLOCK")):
        raise LedgerError("当前平台无法安全核验账本路径")
    if any(not isinstance(part, str) or not part or part in (".", "..") or
           os.path.sep in part for part in parts):
        raise LedgerError("账本路径无效")
    common = os.path.realpath(os.path.dirname(os.path.dirname(os.path.dirname(root))))
    path = os.path.join(common, "spec-guard", "parallel", "v%d" % SCHEMA_VERSION, *parts)
    directory = None
    try:
        # root derives from the canonical Git common-dir; do not realpath untrusted records.
        directory = os.open(os.path.sep, os.O_RDONLY | os.O_DIRECTORY)
        components = os.path.abspath(path).split(os.path.sep)[1:]
        for component in components[:-1]:
            child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
        descriptor = os.open(components[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        with os.fdopen(descriptor, encoding="utf-8") as handle:
            if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
                raise LedgerError("账本记录不是普通文件")
            return json.load(handle)
    except (OSError, ValueError) as error:
        raise LedgerError("账本记录无法安全读取: %s" % error)
    finally:
        if directory is not None:
            os.close(directory)


def load_run(root, requested_id):
    validate_run_id(requested_id)
    run = load_ledger_json(root, "runs", requested_id + ".json")
    run_modules(run)
    if run["runId"] != requested_id:
        raise LedgerError("run 请求、文件名与内容身份不匹配")
    return run


def validate_worker_link(run, worker, worker_id, module_id):
    validate_record(worker, ("schemaVersion", "runId", "baseSha", "workerId", "moduleId"))
    expected = re.escape(run["runId"][:12] + "-" + module_id) + r"-[1-9][0-9]*"
    if (not isinstance(worker_id, str) or not re.fullmatch(expected, worker_id) or
            worker["workerId"] != worker_id or worker["runId"] != run["runId"] or
            worker["moduleId"] != module_id or worker["baseSha"] != run["baseSha"] or
            module_id not in run_modules(run)):
        raise LedgerError("worker 与 run/module 身份不匹配")


def write_json_exclusive(path, value):
    """原子创建 JSON 文件；存在时返回 False，绝不覆盖已有 provenance。"""
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    payload = (json.dumps(value, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except OSError as error:
        if error.errno == 17:
            return False
        raise LedgerError("无法创建账本记录: %s" % error)
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(payload)
    return True


def claim_lease(root, run, module_id):
    """用目录创建的原子性领取单个模块，并生成其 worker manifest。"""
    reject_parallel_write()
    validate_module_id(module_id)
    if module_id not in run_modules(run):
        raise LedgerError("module 不属于该 run")
    lease_root = os.path.join(root, "leases", run["runId"])
    os.makedirs(lease_root, exist_ok=True)
    lease_path = os.path.join(lease_root, "module-" + module_id)
    try:
        os.mkdir(lease_path)
    except OSError as error:
        if error.errno == 17:
            raise ClaimConflict("module 已被其他 worker 领取: %s" % module_id)
        raise LedgerError("无法创建 module lease: %s" % error)
    now = time.time()
    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "runId": run["runId"],
        "workerId": "%s-%s-1" % (run["runId"][:12], module_id),
        "moduleId": module_id,
        "baseSha": run["baseSha"],
        "leasePath": lease_path,
        "owner": getpass.getuser(),
        "createdAt": now,
        "renewedAt": now,
        "status": "active",
    }
    manifest_path = os.path.join(lease_path, "manifest.json")
    if not write_json_exclusive(manifest_path, manifest):
        raise LedgerError("新建 lease 缺少唯一 manifest")
    return manifest_path, manifest


def run_modules(run):
    validate_record(run, ("schemaVersion", "runId", "baseSha", "modules"))
    modules = run.get("modules")
    if not isinstance(modules, list) or not modules:
        raise LedgerError("run modules 无效")
    module_ids = []
    for item in modules:
        if not isinstance(item, dict) or not isinstance(item.get("rowDigest"), str) or not item["rowDigest"]:
            raise LedgerError("run module 无效")
        validate_module_id(item.get("id"))
        module_ids.append(item["id"])
    if len(set(module_ids)) != len(module_ids):
        raise LedgerError("run modules 重复")
    return module_ids


def lease_status(root, run, module_id):
    """只读地将 lease 映射为可安全使用的状态。"""
    try:
        run_modules(run)
        validate_module_id(module_id)
        path = os.path.realpath(os.path.dirname(os.path.dirname(os.path.dirname(root))))
        for component in ("spec-guard", "parallel", "v1", "leases", run["runId"], "module-" + module_id):
            path = os.path.join(path, component)
            try:
                mode = os.lstat(path).st_mode
            except FileNotFoundError:
                return {"moduleId": module_id, "state": "available"}
            if not stat.S_ISDIR(mode):
                raise LedgerError("lease 目录布局无法安全核验")
        manifest = load_ledger_json(root, "leases", run["runId"], "module-" + module_id, "manifest.json")
        validate_record(manifest, ("schemaVersion", "runId", "baseSha", "moduleId", "workerId", "owner", "createdAt", "renewedAt", "status"))
        if (manifest["runId"] != run["runId"] or manifest["baseSha"] != run["baseSha"] or
                manifest["moduleId"] != module_id or not isinstance(manifest["workerId"], str) or
                not manifest["workerId"] or not isinstance(manifest["owner"], str) or not manifest["owner"] or
                not isinstance(manifest["createdAt"], (int, float)) or not isinstance(manifest["renewedAt"], (int, float))):
            raise LedgerError("lease manifest 身份无效")
        if manifest["status"] != "active":
            raise LedgerError("lease 状态不可用: %s" % manifest["status"])
        validate_worker_link(run, manifest, manifest["workerId"], module_id)
        worker = load_ledger_json(root, "workers", manifest["workerId"] + ".json")
        validate_worker_link(run, worker, manifest["workerId"], module_id)
        if worker.get("owner") not in ("host", "spec-guard"):
            raise LedgerError("worker owner 无法核验")
    except (LedgerError, OSError) as error:
        return {"moduleId": module_id, "state": "unknown", "reason": str(error)}
    return {"moduleId": module_id, "state": "claimed", "workerId": manifest["workerId"],
            "reason": "旧领取记录存在；任务完成与可回收性未核验"}
