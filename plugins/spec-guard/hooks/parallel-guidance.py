#!/usr/bin/env python3
import argparse
import json
import os
import sys
from parallel_guidance import guidance
from parallel_safety_gate import gate_report

parser = argparse.ArgumentParser()
parser.add_argument("--project", default=".")
parser.add_argument("--refresh", action="store_true")
parser.add_argument("--format", choices=("text", "json"), default="text")
args = parser.parse_args()
try:
    report = guidance(gate_report(os.path.abspath(args.project), refresh=args.refresh))
except (OSError, RuntimeError) as error:
    print("parallel-guidance: %s" % error, file=sys.stderr)
    raise SystemExit(1)
if args.format == "json":
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
else:
    print("人工并行指引（不会自动创建或回收 worker）")
    for group in report["groups"]:
        for worker in group["workers"]:
            print("- %s: %s / %s" % (worker["module"], worker["branch"], worker["title"]))
