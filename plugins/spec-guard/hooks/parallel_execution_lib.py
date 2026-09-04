#!/usr/bin/env python3
"""Worktree 并行执行账本的身份、路径和记录校验基元。"""
from __future__ import print_function

import hashlib
import os
import re
import subprocess


SCHEMA_VERSION = 1
MODULE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SHA40 = re.compile(r"^[0-9a-f]{40}$")


class LedgerError(Exception):
    """账本输入或本地 Git 身份无法安全验证。"""


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
    if not isinstance(module_id, str) or not MODULE_ID.match(module_id):
        raise LedgerError("module id 必须是 kebab-case")


def validate_record(record, required_fields):
    """验证所有 ledger JSON 记录共享的最小不可变字段。"""
    if not isinstance(record, dict):
        raise LedgerError("账本记录必须是对象")
    if type(record.get("schemaVersion")) is not int or record["schemaVersion"] != SCHEMA_VERSION:
        raise LedgerError("不支持的账本 schema version")
    for field in required_fields:
        if field not in record:
            raise LedgerError("账本记录缺少字段: %s" % field)
    if not isinstance(record.get("runId"), str) or not re.match(r"^[0-9a-f]{64}$", record["runId"]):
        raise LedgerError("runId 无效")
    if not isinstance(record.get("baseSha"), str) or not SHA40.match(record["baseSha"]):
        raise LedgerError("base SHA 无效")
