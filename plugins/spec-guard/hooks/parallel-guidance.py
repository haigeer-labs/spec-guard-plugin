#!/usr/bin/env python3
import argparse
import json
import os
import sys
from parallel_guidance import guidance
from capability_map import MapError
from parallel_safety_gate import BoundaryError, gate_report, group_text

parser = argparse.ArgumentParser()
parser.add_argument("--project", default=".")
parser.add_argument("--refresh", action="store_true")
parser.add_argument("--format", choices=("text", "json"), default="text")
args = parser.parse_args()
try:
    report = guidance(gate_report(os.path.abspath(args.project), refresh=args.refresh))
except (MapError, BoundaryError, OSError, RuntimeError, UnicodeError) as error:
    print("parallel-guidance: %s" % error, file=sys.stderr)
    raise SystemExit(1)
if args.format == "json":
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
else:
    print("人工并行指引（不会自动创建或回收 worker）")
    print("基线: %s @ %s" % (report["base"]["ref"], report["base"]["sha"]))
    print("新鲜度: 已验证" if report["base"]["fresh"] else "新鲜度: 未验证")
    print(report["notice"])
    for warning in report["warnings"]:
        print("警告: " + warning)
    for group in report["groups"]:
        print(group_text(group))
        for worker in group["workers"]:
            print("- %s: %s / %s" % (worker["module"], worker["branch"], worker["title"]))
