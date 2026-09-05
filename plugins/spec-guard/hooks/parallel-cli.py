#!/usr/bin/env python3
"""在已验证的 controller-owned worktree 中运行受控 CLI worker。"""
from __future__ import print_function

import argparse
import json
import os
import tempfile
import time
import sys

from parallel_cli_adapters import CliTimeout, command_for, run_worker
from parallel_execution_lib import (LedgerError, ledger_root, load_json, validate_record,
                                    write_json_exclusive)
from parallel_worktree_lib import load_worker_manifest, verify_worker, worker_path


VALID_STATES = ("started", "completed", "failed", "unknown")


def process_record_path(project, worker_id):
    worker_path(project, worker_id)
    return os.path.join(ledger_root(project), "processes", worker_id + ".json")


def _validate_process_record(record):
    validate_record(record, ("schemaVersion", "runId", "baseSha", "workerId", "moduleId", "host",
                             "worktreePath", "command", "state", "startedAt"))
    if record["state"] not in VALID_STATES:
        raise LedgerError("worker process state 无效")
    if record["host"] not in ("codex-cli", "claude-cli"):
        raise LedgerError("worker process host 无效")
    if not isinstance(record["command"], list) or not all(isinstance(value, str) for value in record["command"]):
        raise LedgerError("worker process command 无效")
    if not isinstance(record["startedAt"], (int, float)):
        raise LedgerError("worker process startedAt 无效")
    if record["state"] == "started":
        if "finishedAt" in record or "returncode" in record:
            raise LedgerError("started worker process 不应有终态")
    else:
        if not isinstance(record.get("finishedAt"), (int, float)):
            raise LedgerError("worker process finishedAt 无效")
    if record["state"] in ("completed", "failed") and type(record.get("returncode")) is not int:
        raise LedgerError("worker process returncode 无效")
    if record["state"] == "unknown" and not isinstance(record.get("reason"), str):
        raise LedgerError("unknown worker process 缺少原因")


def _replace_record(path, record):
    _validate_process_record(record)
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".process-", dir=parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(record, handle, ensure_ascii=False, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, path)
    except OSError as error:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise LedgerError("无法更新 worker process record: %s" % error)


def start_worker(project, worker_id, host, timeout_seconds=None):
    project = os.path.abspath(project)
    manifest = load_worker_manifest(project, worker_id)
    ready = verify_worker(project, manifest)
    if ready.get("ok") is not True:
        raise LedgerError("worker 不可启动: %s" % ready.get("reason", "unknown"))
    command = command_for(host, manifest["worktreePath"], {"codex-cli": "codex", "claude-cli": "claude"}.get(host, ""))
    record = {
        "schemaVersion": 1,
        "runId": manifest["runId"],
        "baseSha": manifest["baseSha"],
        "workerId": manifest["workerId"],
        "moduleId": manifest["moduleId"],
        "host": host,
        "worktreePath": manifest["worktreePath"],
        "command": command,
        "state": "started",
        "startedAt": time.time(),
    }
    _validate_process_record(record)
    path = process_record_path(project, worker_id)
    if not write_json_exclusive(path, record):
        raise LedgerError("worker 已有 process record，拒绝重复启动")
    try:
        result = run_worker(host, manifest["worktreePath"], timeout_seconds=timeout_seconds)
        record.update(result, finishedAt=time.time())
    except CliTimeout as error:
        record.update(state="unknown", reason=str(error), finishedAt=time.time())
    except KeyboardInterrupt:
        record.update(state="unknown", reason="host CLI 被中断", finishedAt=time.time())
    except LedgerError as error:
        record.update(state="unknown", reason=str(error), finishedAt=time.time())
    _replace_record(path, record)
    return record


def inspect_worker(project, worker_id):
    """只读检查已记录的 worker；任何无法证明的状态都显式降为 unknown。"""
    project = os.path.abspath(project)
    try:
        manifest = load_worker_manifest(project, worker_id)
        record = load_json(process_record_path(project, worker_id), "worker process record")
        _validate_process_record(record)
        for field in ("runId", "baseSha", "workerId", "moduleId", "worktreePath"):
            if record[field] != manifest[field]:
                raise LedgerError("worker process 与 manifest 身份不匹配")
        executable = {"codex-cli": "codex", "claude-cli": "claude"}[record["host"]]
        if record["command"] != command_for(record["host"], manifest["worktreePath"], executable):
            raise LedgerError("worker process command 不匹配")
        if record["state"] == "started":
            return {"ok": False, "workerId": worker_id, "state": "unknown",
                    "reason": "worker process 未写入终态"}
        if record["state"] == "unknown":
            return {"ok": False, "workerId": worker_id, "state": "unknown",
                    "reason": record["reason"]}
    except (LedgerError, OSError, ValueError, KeyError) as error:
        return {"ok": False, "workerId": worker_id, "state": "unknown", "reason": str(error)}
    return {"ok": True, "workerId": worker_id, "state": record["state"],
            "returncode": record["returncode"]}


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    start = commands.add_parser("start")
    start.add_argument("--project", default=".")
    start.add_argument("--worker", required=True)
    start.add_argument("--host", required=True, choices=("codex-cli", "claude-cli"))
    start.add_argument("--timeout-seconds", type=float)
    start.add_argument("--format", choices=("text", "json"), default="text")
    inspect = commands.add_parser("inspect")
    inspect.add_argument("--project", default=".")
    inspect.add_argument("--worker", required=True)
    inspect.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)
    try:
        if args.command == "start":
            result = start_worker(args.project, args.worker, args.host, args.timeout_seconds)
        else:
            result = inspect_worker(args.project, args.worker)
    except (LedgerError, OSError, ValueError, KeyError) as error:
        print("parallel-cli: %s" % error, file=sys.stderr)
        return 1
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    else:
        detail = " (%s)" % result["reason"] if result.get("reason") else ""
        print("%s: %s%s" % (result["workerId"], result["state"], detail))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
