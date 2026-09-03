#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT/hooks" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from parallel_guidance import guidance

report = {"base": {"sha": "a" * 40, "fresh": False}, "warnings": [], "groups": [
    {"layer": 0, "modules": ["alpha", "beta"], "classification": "manual-parallel-eligible", "evidence": []},
    {"layer": 1, "modules": ["gamma", "delta"], "classification": "sequential-required", "evidence": [{"category": "paths"}]},
]}
result = guidance(report)
assert result["base"] == report["base"]
assert [item["branch"] for item in result["groups"][0]["workers"]] == ["codex/parallel/alpha", "codex/parallel/beta"]
assert result["groups"][1]["workers"] == []
assert all("自动" not in item for item in result["mergeChecklist"])
PY
printf 'parallel-guidance regression passed\n'
