#!/usr/bin/env python3
"""创建、复验和回收 controller-owned Spec Guard worker worktree。"""
from __future__ import print_function

import argparse
import json
import os
import subprocess
import sys

from parallel_execution_lib import (ClaimConflict, LedgerError, ParallelWritesDisabled,
                                    claim_lease, ledger_root, load_json, reject_parallel_write,
                                    validate_run_id)
from parallel_worktree_lib import (load_worker_manifest, provision, reclaim, verify_worker,
                                   worker_path)


def _git_common_dir(project):
    result = subprocess.run(["git", "-C", project, "rev-parse", "--git-common-dir"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise LedgerError(result.stderr.strip() or "无法读取 Git common-dir")
    common = result.stdout.strip()
    return common if os.path.isabs(common) else os.path.abspath(os.path.join(project, common))


def provision_worker(project, run_id_value, module_id):
    reject_parallel_write()
    project = os.path.abspath(project)
    validate_run_id(run_id_value)
    root = ledger_root(project)
    run = load_json(os.path.join(root, "runs", run_id_value + ".json"), "run")
    _, lease = claim_lease(root, run, module_id)
    worker_id = lease["workerId"]
    manifest = dict(lease, owner="spec-guard", gitCommonDir=_git_common_dir(project),
                    worktreePath=worker_path(project, worker_id), branch="spec-guard/" + worker_id)
    return {"ok": True, "manifest": provision(project, manifest)}


def inspect_worker(project, worker_id):
    manifest = load_worker_manifest(project, worker_id)
    return verify_worker(project, manifest)


def reclaim_worker(project, worker_id, merged, confirm):
    reject_parallel_write()
    manifest = load_worker_manifest(project, worker_id)
    return reclaim(project, manifest, merged=merged, confirm=confirm)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    provision_parser = commands.add_parser("provision")
    provision_parser.add_argument("--project", default=".")
    provision_parser.add_argument("--run", required=True)
    provision_parser.add_argument("--module", required=True)
    provision_parser.add_argument("--format", choices=("text", "json"), default="text")
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("--project", default=".")
    verify_parser.add_argument("--worker", required=True)
    verify_parser.add_argument("--format", choices=("text", "json"), default="text")
    reclaim_parser = commands.add_parser("reclaim")
    reclaim_parser.add_argument("--project", default=".")
    reclaim_parser.add_argument("--worker", required=True)
    reclaim_parser.add_argument("--merged", action="store_true")
    reclaim_parser.add_argument("--confirm", action="store_true")
    reclaim_parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)
    try:
        if args.command == "provision":
            result = provision_worker(args.project, args.run, args.module)
        elif args.command == "verify":
            result = inspect_worker(args.project, args.worker)
        else:
            result = reclaim_worker(args.project, args.worker, args.merged, args.confirm)
    except ParallelWritesDisabled as error:
        result = {"ok": False, "code": error.code, "message": str(error)}
        if args.format == "json":
            print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        else:
            print("parallel-worktree: %s: %s" % (error.code, error), file=sys.stderr)
        return 1
    except ClaimConflict as error:
        result = {"ok": False, "code": "CONFLICT", "message": str(error)}
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 1
    except (LedgerError, OSError, ValueError, KeyError) as error:
        print("parallel-worktree: %s" % error, file=sys.stderr)
        return 1
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    elif args.command == "provision":
        print("已创建 worker %s" % result["manifest"]["workerId"])
    elif args.command == "verify":
        print("%s: %s" % (args.worker, result["state"]))
    else:
        print("%s: %s" % (result["workerId"], result["state"]))
    return 0 if result.get("ok") is True else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
