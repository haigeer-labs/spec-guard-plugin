#!/usr/bin/env python3
"""创建并查询 Spec Guard Worktree 并行执行 run。"""
from __future__ import print_function

import argparse
import importlib.util
import json
import os
import sys

from parallel_execution_lib import (
    LedgerError,
    current_head,
    ledger_root,
    load_json,
    origin_remote,
    run_id,
    validate_record,
    write_json_exclusive,
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


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    create = subcommands.add_parser("create-run")
    create.add_argument("--project", default=".")
    create.add_argument("--safety-report", required=True)
    create.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)
    try:
        result = create_run(args.project, args.safety_report)
    except (LedgerError, OSError, ValueError, KeyError) as error:
        print("parallel-execution: %s" % error, file=sys.stderr)
        return 1
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    else:
        state = "已创建" if result["created"] else "已复用"
        print("%s run %s" % (state, result["run"]["runId"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
