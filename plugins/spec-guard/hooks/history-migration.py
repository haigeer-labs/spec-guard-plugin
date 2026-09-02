#!/usr/bin/env python3
"""Produce a conservative, read-only preview of legacy spec-guard evidence."""
import json
import os
import sys


def preview(project):
    result = {"candidates": [], "conflicts": []}
    if os.path.exists(os.path.join(project, "spec", "CAPABILITY-HISTORY.json")):
        result["conflicts"].append("capability history ledger already exists")
        return result
    paths = {
        "map": "CAPABILITY-MAP.md",
        "state": ".agent/state.json",
    }
    found = {name: path for name, path in paths.items() if os.path.isfile(os.path.join(project, path))}
    specs = sorted(name for name in os.listdir(project) if name.startswith("SPEC-") and name.endswith(".md")) if os.path.isdir(project) else []
    if not found and not specs:
        return result
    result["candidates"].append({"id": "legacy", "evidence": found, "legacySpecs": specs, "status": "unknown"})
    return result


def main(argv):
    if len(argv) != 2 or argv[0] != "preview":
        print("usage: history-migration.py preview <project>", file=sys.stderr)
        return 2
    print(json.dumps(preview(argv[1]), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
