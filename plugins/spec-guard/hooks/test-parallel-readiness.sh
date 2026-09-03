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

printf 'parallel-readiness parser regression passed\n'
