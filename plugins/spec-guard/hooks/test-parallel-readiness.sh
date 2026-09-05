#!/bin/bash
# parallel-readiness 的确定性回归。当前第一组只锁定能力图共享解析契约。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

write_map() {
  local name="$1"
  cat > "$WORK/$name.md"
}

write_map valid <<'EOF'
# Capability Map: test

## 目标

测试共享解析。

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| alpha | 根模块 | — |
| beta | 第二根模块 | - |
| gamma | 下游模块 | alpha, beta |

Build order: alpha → beta → gamma
EOF

write_map unknown <<'EOF'
# Capability Map: test

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| alpha | 根模块 | absent |

Build order: alpha
EOF

write_map cycle <<'EOF'
# Capability Map: test

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| alpha | A | beta |
| beta | B | alpha |

Build order: alpha → beta
EOF

write_map self <<'EOF'
# Capability Map: test

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| alpha | A | alpha |

Build order: alpha
EOF

write_map invalid_id <<'EOF'
# Capability Map: test

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| Alpha_Module | A | — |

Build order: Alpha_Module
EOF

write_map bad_order <<'EOF'
# Capability Map: test

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| alpha | A | — |
| beta | B | alpha |

Build order: beta → alpha
EOF

python3 - "$ROOT/hooks" "$WORK" <<'PY'
import sys

hooks, work = sys.argv[1:]
sys.path.insert(0, hooks)

from capability_map import MapError, parse_map

parsed = parse_map(work + "/valid.md")
assert parsed.order == ["alpha", "beta", "gamma"], parsed.order
assert [row.module_id for row in parsed.rows] == ["alpha", "beta", "gamma"]
assert parsed.rows[2].depends_on == ["alpha", "beta"]

for name in ("unknown", "cycle", "self", "invalid_id", "bad_order"):
    try:
        parse_map(work + "/%s.md" % name)
    except MapError:
        pass
    else:
        raise AssertionError("%s map should be rejected" % name)
PY

git init --bare -q "$WORK/remote.git"
git init -q "$WORK/project"
git -C "$WORK/project" config user.email test@example.invalid
git -C "$WORK/project" config user.name test
mkdir -p "$WORK/project/spec"
cp "$WORK/valid.md" "$WORK/project/spec/CAPABILITY-MAP.md"
git -C "$WORK/project" add spec/CAPABILITY-MAP.md
git -C "$WORK/project" commit -qm "test map"
git -C "$WORK/project" branch -M trunk
git -C "$WORK/project" remote add origin "$WORK/remote.git"
git -C "$WORK/project" push -qu origin trunk
git -C "$WORK/remote.git" symbolic-ref HEAD refs/heads/trunk
git -C "$WORK/project" fetch -q origin
git -C "$WORK/project" remote set-head origin -a

python3 - "$ROOT/hooks/parallel-readiness.py" "$WORK/project" <<'PY'
import json
import subprocess
import sys

script, project = sys.argv[1:]
before = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
result = subprocess.run(
    ["python3", script, "--project", project, "--format", "json"],
    check=True, capture_output=True, text=True,
)
report = json.loads(result.stdout)
assert report["ok"] is True, report
assert report["base"] == {"ref": "origin/trunk", "sha": before, "fresh": False}, report
assert report["candidateGroups"] == [{
    "layer": 0,
    "modules": ["alpha", "beta"],
    "classification": "candidate-only",
}], report
assert any("尚未验证远端新鲜度" in warning for warning in report["warnings"]), report
after = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
assert after == before
assert subprocess.check_output(
    ["git", "-C", project, "rev-parse", "origin/trunk"], text=True
).strip() == before
PY

git clone -q "$WORK/remote.git" "$WORK/publisher"
git -C "$WORK/publisher" config user.email test@example.invalid
git -C "$WORK/publisher" config user.name test
printf 'remote advance\n' > "$WORK/publisher/README.md"
git -C "$WORK/publisher" add README.md
git -C "$WORK/publisher" commit -qm "advance remote"
git -C "$WORK/publisher" push -q origin trunk

python3 - "$ROOT/hooks/parallel-readiness.py" "$WORK/project" <<'PY'
import json
import subprocess
import sys

script, project = sys.argv[1:]
head_before = subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip()
remote_before = subprocess.check_output(
    ["git", "-C", project, "rev-parse", "origin/trunk"], text=True
).strip()
published = subprocess.check_output(
    ["git", "-C", project + "/../publisher", "rev-parse", "HEAD"], text=True
).strip()
result = subprocess.run(
    ["python3", script, "--project", project, "--refresh", "--format", "json"],
    check=True, capture_output=True, text=True,
)
report = json.loads(result.stdout)
assert remote_before != published
assert report["base"] == {"ref": "origin/trunk", "sha": published, "fresh": True}, report
assert not report["warnings"], report
assert "未核验任务状态" in report["notice"], report
assert "不表示可立即领取或执行" in report["notice"], report
assert all(group["classification"] == "candidate-only" for group in report["candidateGroups"]), report
assert subprocess.check_output(["git", "-C", project, "rev-parse", "HEAD"], text=True).strip() == head_before

subprocess.run(["git", "-C", project, "remote", "set-url", "origin", project + "/../missing.git"], check=True)
failed = subprocess.run(
    ["python3", script, "--project", project, "--refresh", "--format", "json"],
    capture_output=True, text=True,
)
assert failed.returncode != 0
assert not failed.stdout.strip(), failed.stdout
assert "parallel-readiness:" in failed.stderr, failed.stderr
PY

printf 'parallel-readiness regression passed\n'
