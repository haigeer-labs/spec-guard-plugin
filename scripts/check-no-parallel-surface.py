#!/usr/bin/env python3
"""Fail if the retired parallel workflow leaks into the live plugin surface."""
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    forbidden_files = []
    for pattern in (
        "plugins/spec-guard/commands/parallel-*.md",
        "plugins/spec-guard/hooks/parallel-*.py",
        "plugins/spec-guard/hooks/parallel_*.py",
        "plugins/spec-guard/hooks/test-parallel-*.sh",
        "plugins/spec-guard/hooks/test_parallel_*.py",
        "spec/parallel-*.md",
        "tasks/parallel-*",
    ):
        forbidden_files.extend(ROOT.glob(pattern))

    live_plugin = ROOT / "plugins/spec-guard"
    leaked_references = []
    pattern = re.compile(r"parallel[-_]|PARALLEL_WRITES_DISABLED")
    for path in live_plugin.rglob("*"):
        if not path.is_file() or path.suffix not in {".md", ".py", ".sh", ".mjs", ".json"}:
            continue
        if pattern.search(path.read_text(encoding="utf-8")):
            leaked_references.append(path)

    problems = sorted({str(path.relative_to(ROOT)) for path in forbidden_files if path.is_file()}
                      | {str(path.relative_to(ROOT)) for path in leaked_references})
    if problems:
        print("parallel workflow remains in the live surface:", file=sys.stderr)
        print("\n".join("- " + path for path in problems), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
