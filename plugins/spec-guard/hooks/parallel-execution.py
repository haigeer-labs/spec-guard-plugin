#!/usr/bin/env python3
"""创建并查询 Spec Guard Worktree 并行执行 run。"""
from __future__ import print_function

import argparse
import importlib.util
import json
import os
import sys

from parallel_execution_lib import (
    ClaimConflict,
    LedgerError,
    ParallelWritesDisabled,
    claim_lease,
    current_head,
    ledger_root,
    lease_status,
    load_json,
    load_run,
    origin_remote,
    run_id,
    validate_record,
    validate_run_id,
    write_json_exclusive,
    run_modules,
    reject_parallel_write,
)


def _compute_digest(path):
    script = os.path.join(os.path.dirname(__file__), "spec-digest.py")
    spec = importlib.util.spec_from_file_location("parallel_execution_digest", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.compute(path)


def _eligible_modules(report, map_order):
    if not isinstance(report, dict) or report.get("ok") is not True:
        raise LedgerError("safety report 不是成功结果")
    base = report.get("base")
    if not isinstance(base, dict) or not isinstance(base.get("sha"), str):
        raise LedgerError("safety report 缺少 base SHA")
    groups = report.get("groups")
    if not isinstance(groups, list):
        raise LedgerError("safety report groups 无效")
    eligible = [group for group in groups if isinstance(group, dict) and
                group.get("classification") == "manual-parallel-eligible"]
    if len(eligible) != 1:
        raise LedgerError("safety report 必须恰好有一个 eligible 模块组")
    modules = eligible[0].get("modules")
    if not isinstance(modules, list) or not modules or any(not isinstance(item, str) for item in modules):
        raise LedgerError("eligible 模块组无效")
    expected = [module for module in map_order if module in modules]
    if modules != expected or len(set(modules)) != len(modules):
        raise LedgerError("eligible 模块顺序与 capability map 不一致")
    return report["base"]["sha"], modules


def create_run(project, safety_report_path):
    reject_parallel_write()
    project = os.path.abspath(project)
    report = load_json(safety_report_path, "safety report")
    map_path = os.path.join(project, "spec", "CAPABILITY-MAP.md")
    digest = _compute_digest(map_path)
    if digest.get("placeholder") or not digest.get("goalDigest"):
        raise LedgerError("capability map 不是可执行的已评审输入")
    base_sha, modules = _eligible_modules(report, digest["order"])
    head = current_head(project)
    if base_sha != head:
        raise LedgerError("safety report base SHA 与当前 HEAD 不一致")
    rows = dict((row["id"], row["rowDigest"]) for row in digest["rows"])
    module_rows = [{"id": module, "rowDigest": rows[module]} for module in modules]
    identity = run_id(origin_remote(project), head, digest["goalDigest"],
                      [row["rowDigest"] for row in module_rows])
    record = {
        "schemaVersion": 1,
        "runId": identity,
        "baseSha": head,
        "goalDigest": digest["goalDigest"],
        "modules": module_rows,
    }
    validate_record(record, ("schemaVersion", "runId", "baseSha", "goalDigest", "modules"))
    path = os.path.join(ledger_root(project), "runs", identity + ".json")
    created = write_json_exclusive(path, record)
    if not created:
        existing = load_json(path, "已有 run")
        if existing != record:
            raise LedgerError("已有同名 run 与当前 provenance 不兼容")
    return {"ok": True, "created": created, "path": path, "run": record}


def claim_module(project, run_id_value, module_id):
    reject_parallel_write()
    project = os.path.abspath(project)
    validate_run_id(run_id_value)
    path = os.path.join(ledger_root(project), "runs", run_id_value + ".json")
    run = load_json(path, "run")
    manifest_path, manifest = claim_lease(ledger_root(project), run, module_id)
    return {"ok": True, "path": manifest_path, "manifest": manifest}


def status_run(project, run_id_value):
    project = os.path.abspath(project)
    try:
        validate_run_id(run_id_value)
        root = ledger_root(project)
        run = load_run(root, run_id_value)
        modules = run_modules(run)
    except LedgerError as error:
        return {"ok": False, "runId": run_id_value, "state": "unknown", "reason": str(error), "modules": []}
    states = [lease_status(root, run, module_id) for module_id in modules]
    from parallel_worktree_lib import load_worker_manifest, verify_worker
    for state in states:
        if state["state"] != "claimed":
            continue
        try:
            manifest = load_worker_manifest(project, state["workerId"])
            status = verify_worker(project, manifest)
            if status.get("ok") is not True:
                raise LedgerError(status.get("reason", "worker 资源无法核验"))
        except (LedgerError, OSError, ValueError, KeyError) as error:
            state.update(state="unknown", reason=str(error))
    return {"ok": all(item["state"] != "unknown" for item in states), "runId": run["runId"],
            "baseSha": run["baseSha"], "modules": states}


def status_details(project, run_id_value):
    """Aggregate read-only diagnostics without hiding a failed child query."""
    result = status_run(project, run_id_value)
    result["workers"] = []
    from parallel_worktree_lib import load_worker_manifest, verify_worker
    spec = importlib.util.spec_from_file_location("parallel_cli_status", os.path.join(os.path.dirname(__file__), "parallel-cli.py"))
    cli = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cli)
    for module in result["modules"]:
        worker_id = module.get("workerId")
        if not worker_id:
            continue
        try:
            manifest = load_worker_manifest(project, worker_id)
            runtime = verify_worker(project, manifest)
            entry = {"workerId": worker_id, "runtime": runtime}
            if manifest["owner"] != "host":
                entry["process"] = cli.inspect_worker(project, worker_id)
            if not runtime.get("ok") or not entry.get("process", {"ok": True}).get("ok"):
                result["ok"] = False
        except (LedgerError, OSError, ValueError, KeyError) as error:
            entry = {"workerId": worker_id, "state": "unknown", "reason": str(error)}
            result["ok"] = False
        result["workers"].append(entry)
    return result


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    create = subcommands.add_parser("create-run")
    create.add_argument("--project", default=".")
    create.add_argument("--safety-report", required=True)
    create.add_argument("--format", choices=("text", "json"), default="text")
    claim = subcommands.add_parser("claim-module")
    claim.add_argument("--project", default=".")
    claim.add_argument("--run", required=True)
    claim.add_argument("--module", required=True)
    claim.add_argument("--format", choices=("text", "json"), default="text")
    status = subcommands.add_parser("status")
    status.add_argument("--project", default=".")
    status.add_argument("--run", required=True)
    status.add_argument("--format", choices=("text", "json"), default="text")
    status.add_argument("--details", action="store_true", help="汇总只读 worker 与 process 诊断")
    args = parser.parse_args(argv)
    try:
        if args.command == "create-run":
            result = create_run(args.project, args.safety_report)
        elif args.command == "claim-module":
            result = claim_module(args.project, args.run, args.module)
        else:
            result = status_details(args.project, args.run) if args.details else status_run(args.project, args.run)
    except ParallelWritesDisabled as error:
        result = {"ok": False, "code": error.code, "message": str(error)}
        if args.format == "json":
            print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        else:
            print("parallel-execution: %s: %s" % (error.code, error), file=sys.stderr)
        return 1
    except ClaimConflict as error:
        result = {"ok": False, "code": "CONFLICT", "message": str(error)}
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 1
    except (LedgerError, OSError, ValueError, KeyError) as error:
        print("parallel-execution: %s" % error, file=sys.stderr)
        return 1
    if args.format == "json" or (args.command == "status" and args.details):
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    else:
        if args.command == "create-run":
            state = "已创建" if result["created"] else "已复用"
            print("%s run %s" % (state, result["run"]["runId"]))
        elif args.command == "claim-module":
            print("已领取 module %s" % result["manifest"]["moduleId"])
        elif result.get("state") == "unknown":
            print("run %s: unknown (%s)" % (result["runId"], result["reason"]))
        else:
            for item in result["modules"]:
                detail = " (%s)" % item["reason"] if "reason" in item else ""
                print("%s: %s%s" % (item["moduleId"], item["state"], detail))
    return 0 if result.get("ok") is True else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
