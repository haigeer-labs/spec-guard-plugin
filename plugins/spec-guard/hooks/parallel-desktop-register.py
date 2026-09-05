#!/usr/bin/env python3
"""登记已存在的 Codex/Claude Desktop linked worktree，不管理宿主资源。"""
from __future__ import print_function

import argparse
import json
import os
import re
import subprocess
import sys
import time

from parallel_execution_lib import (ClaimConflict, LedgerError, ParallelWritesDisabled,
                                    reject_parallel_write, claim_lease, ledger_root,
                                    load_json, run_modules, validate_module_id,
                                    validate_run_id, write_json_exclusive)


HOSTS = ("codex-desktop", "claude-desktop")
HOST_WORKER_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$")


def _git(path, *args):
    result = subprocess.run(["git", "-C", path] + list(args), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise LedgerError(result.stderr.strip() or "git 命令失败")
    return result.stdout.strip()


def _common_dir(path):
    common = _git(path, "rev-parse", "--git-common-dir")
    return common if os.path.isabs(common) else os.path.abspath(os.path.join(path, common))


def _is_linked_worktree(project, cwd):
    lines = _git(project, "worktree", "list", "--porcelain").splitlines()
    git_dir = _git(cwd, "rev-parse", "--git-dir")
    if not os.path.isabs(git_dir):
        git_dir = os.path.abspath(os.path.join(cwd, git_dir))
    return any(line == "worktree " + cwd for line in lines) and _common_dir(project) != git_dir


def _ensure_unique_host_worker(root, run_id_value, host, host_worker_id, cwd):
    workers = os.path.join(root, "workers")
    if not os.path.isdir(workers):
        return
    for name in os.listdir(workers):
        if not name.endswith(".json"):
            continue
        manifest = load_json(os.path.join(workers, name), "worker manifest")
        if manifest.get("owner") != "host" or manifest.get("runId") != run_id_value:
            continue
        if manifest.get("host") == host and manifest.get("hostWorkerId") == host_worker_id:
            raise LedgerError("稳定 host worker ID 已登记到当前 run")
        if os.path.realpath(manifest.get("worktreePath", "")) == cwd:
            raise LedgerError("Desktop worktree 已登记到当前 run")


def _host_manifest(project, run_id_value, module_id, host, host_worker_id, cwd):
    reject_parallel_write()
    if host not in HOSTS:
        raise LedgerError("不支持的 Desktop host")
    if not isinstance(host_worker_id, str) or not HOST_WORKER_ID.match(host_worker_id):
        raise LedgerError("缺少稳定 host worker ID")
    project, cwd = os.path.realpath(project), os.path.realpath(cwd)
    if _git(cwd, "rev-parse", "--show-toplevel") != cwd:
        raise LedgerError("cwd 必须是 Desktop worker 的 Git 根目录")
    if _git(cwd, "rev-parse", "--show-superproject-working-tree"):
        raise LedgerError("submodule 不能登记为 Desktop worker")
    if _common_dir(project) != _common_dir(cwd) or not _is_linked_worktree(project, cwd):
        raise LedgerError("cwd 不属于当前项目的 linked worktree")
    branch = _git(cwd, "branch", "--show-current")
    if not branch:
        raise LedgerError("detached HEAD 不能登记为 Desktop worker")
    root = ledger_root(project)
    run = load_json(os.path.join(root, "runs", run_id_value + ".json"), "run")
    if module_id not in run_modules(run):
        raise LedgerError("module 不属于该 run")
    _ensure_unique_host_worker(root, run_id_value, host, host_worker_id, cwd)
    head = _git(cwd, "rev-parse", "HEAD")
    if subprocess.run(["git", "-C", cwd, "merge-base", "--is-ancestor", run["baseSha"], head]).returncode:
        raise LedgerError("Desktop worker HEAD 未从 run base 演进")
    _, lease = claim_lease(root, run, module_id)
    worker_id = lease["workerId"]
    return root, worker_id, {
        "schemaVersion": 1,
        "runId": run_id_value,
        "workerId": worker_id,
        "moduleId": module_id,
        "baseSha": run["baseSha"],
        "owner": "host",
        "host": host,
        "hostWorkerId": host_worker_id,
        "gitCommonDir": _common_dir(project),
        "worktreePath": cwd,
        "branch": branch,
        "registeredAt": time.time(),
    }


def register(project, run_id_value, module_id, host, host_worker_id, cwd):
    reject_parallel_write()
    project = os.path.abspath(project)
    validate_run_id(run_id_value)
    validate_module_id(module_id)
    root, worker_id, manifest = _host_manifest(project, run_id_value, module_id, host,
                                                host_worker_id, cwd)
    path = os.path.join(root, "workers", worker_id + ".json")
    if not write_json_exclusive(path, manifest):
        raise LedgerError("worker manifest 已存在")
    return {"ok": True, "manifest": manifest}


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("register")
    command.add_argument("--project", default=".")
    command.add_argument("--run", required=True)
    command.add_argument("--module", required=True)
    command.add_argument("--host", required=True, choices=HOSTS)
    command.add_argument("--host-worker-id", required=True)
    command.add_argument("--cwd", required=True)
    command.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)
    try:
        result = register(args.project, args.run, args.module, args.host, args.host_worker_id,
                          args.cwd)
    except ParallelWritesDisabled as error:
        if args.format == "json":
            print(json.dumps({"ok": False, "code": error.code, "message": str(error)}, ensure_ascii=False))
        else:
            print("parallel-desktop-register: %s: %s" % (error.code, error), file=sys.stderr)
        return 1
    except ClaimConflict as error:
        print(json.dumps({"ok": False, "code": "CONFLICT", "message": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    except (LedgerError, OSError, ValueError, KeyError) as error:
        print("parallel-desktop-register: %s" % error, file=sys.stderr)
        return 1
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    else:
        print("已登记 host worker %s" % result["manifest"]["workerId"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
