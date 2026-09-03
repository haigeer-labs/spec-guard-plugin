#!/usr/bin/env python3
import argparse
import json
import os
import sys

from parallel_safety_gate import BoundaryError, gate_report


def main(argv):
    parser = argparse.ArgumentParser(description="保守审查并行候选的显式边界声明")
    parser.add_argument("--project", default=".")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args(argv)
    try:
        report = gate_report(os.path.abspath(args.project), refresh=args.refresh)
    except (BoundaryError, OSError, RuntimeError) as error:
        print("parallel-safety-gate: %s" % error, file=sys.stderr)
        return 1
    if args.format == "json":
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        print("并行安全门（不自动执行）")
        print("基线: %s @ %s" % (report["base"]["ref"], report["base"]["sha"]))
        for group in report["groups"]:
            print("- layer %s: %s [%s]" % (group["layer"], ", ".join(group["modules"]), group["classification"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
