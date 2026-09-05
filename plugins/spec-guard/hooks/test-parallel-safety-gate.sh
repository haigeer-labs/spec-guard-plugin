#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

write_spec() { cat > "$WORK/$1.md"; }

write_spec valid <<'EOF'
# Spec: alpha

## Parallel Boundary

```json
{"paths":["src/alpha.py"],"publicInterfaces":[],"migrations":[],"globalConfig":[],"testResources":[]}
```
EOF
write_spec missing <<'EOF'
# Spec: alpha
EOF
write_spec escape <<'EOF'
## Parallel Boundary
```json
{"paths":["../secret"],"publicInterfaces":[],"migrations":[],"globalConfig":[],"testResources":[]}
```
EOF
write_spec incomplete <<'EOF'
## Parallel Boundary
```json
{"paths":[]}
```
EOF
write_spec beta <<'EOF'
## Parallel Boundary
```json
{"paths":["src/beta.py"],"publicInterfaces":[],"migrations":[],"globalConfig":[],"testResources":[]}
```
EOF
write_spec duplicate <<'EOF'
## Parallel Boundary
```json
{"paths":[],"publicInterfaces":[],"migrations":[],"globalConfig":[],"testResources":[]}
```
## Parallel Boundary
```json
{"paths":[],"publicInterfaces":[],"migrations":[],"globalConfig":[],"testResources":[]}
```
EOF

python3 - "$ROOT/hooks" "$WORK" <<'PY'
import sys
hooks, work = sys.argv[1:]
sys.path.insert(0, hooks)
import parallel_safety_gate as gate
from parallel_safety_gate import BoundaryError, classify_group, parse_boundary

boundary = parse_boundary(work + "/valid.md")
assert boundary["paths"] == ["src/alpha.py"], boundary
for name in ("missing", "escape", "incomplete", "duplicate"):
    try:
        parse_boundary(work + "/%s.md" % name)
    except BoundaryError:
        pass
    else:
        raise AssertionError("%s should be rejected" % name)

empty = {"paths": [], "publicInterfaces": [], "migrations": [], "globalConfig": [], "testResources": []}
eligible = classify_group({
    "alpha": dict(empty, paths=["src/alpha.py"]),
    "beta": dict(empty, paths=["src/beta.py"]),
})
assert eligible["classification"] == "manual-parallel-eligible" and eligible["evidence"] == [], eligible
assert eligible["pathDeclarations"]["alpha"] == [{"raw": "src/alpha.py", "normalized": "src/alpha.py"}], eligible
for field, left, right in (
    ("paths", ["src"], ["src/beta.py"]),
    ("publicInterfaces", ["api.v1"], ["api.v1"]),
    ("testResources", ["db:test"], []),
):
    result = classify_group({
        "alpha": dict(empty, **{field: left}),
        "beta": dict(empty, **{field: right}),
    })
    assert result["classification"] == "sequential-required", result
    assert result["evidence"], result

gate.readiness_report = lambda project, refresh=False: {
    "base": {"ref": "origin/trunk", "sha": "a" * 40, "fresh": refresh},
    "candidateGroups": [{"layer": 0, "modules": ["valid", "beta"], "classification": "candidate-only"}],
    "warnings": [],
}
import os
project = os.path.join(work, "project")
os.makedirs(os.path.join(project, "spec"))
for name in ("valid", "beta"):
    with open(os.path.join(work, name + ".md"), encoding="utf-8") as src:
        with open(os.path.join(project, "spec", name + ".md"), "w", encoding="utf-8") as dst:
            dst.write(src.read())
report = gate.gate_report(project, refresh=True)
assert report["base"]["fresh"] is True, report
assert report["groups"][0]["classification"] == "manual-parallel-eligible", report
PY

printf 'parallel-safety-gate regression passed\n'
