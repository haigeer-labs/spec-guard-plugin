#!/usr/bin/env python3
"""在已验证的 controller-owned worktree 中运行受控 CLI worker。"""
from __future__ import print_function

import argparse
import json
import os
import tempfile
import time
import sys

from parallel_cli_adapters import command_for, run_worker
from parallel_execution_lib import LedgerError, ledger_root, validate_record, write_json_exclusive
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


def start_worker(project, worker_id, host):
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
        result = run_worker(host, manifest["worktreePath"])
        record.update(result, finishedAt=time.time())
    except KeyboardInterrupt:
        record.update(state="unknown", reason="host CLI 被中断", finishedAt=time.time())
    except LedgerError as error:
        record.update(state="unknown", reason=str(error), finishedAt=time.time())
    _replace_record(path, record)
    return record


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    start = commands.add_parser("start")
    start.add_argument("--project", default=".")
    start.add_argument("--worker", required=True)
    start.add_argument("--host", required=True, choices=("codex-cli", "claude-cli"))
    start.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)
    try:
        result = start_worker(args.project, args.worker, args.host)
    except (LedgerError, OSError, ValueError, KeyError) as error:
        print("parallel-cli: %s" % error, file=sys.stderr)
        return 1
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    else:
        print("%s: %s" % (result["workerId"], result["state"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
