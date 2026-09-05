#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT/scripts/release-evidence.py"
GUIDE="$ROOT/docs/releases/README.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok() { printf '  ✅ %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL + 1)); }

write() { printf '%s\n' "$2" > "$1"; }

VALID="$TMP/valid.json"
write "$VALID" '{"schemaVersion":1,"release":{"version":"0.8.0"},"records":[{"subject":"codex-cli","status":"source-verified","target":{"kind":"source-checkout","id":"commit:abc"},"observedAt":"2026-09-05T14:00:00Z","evidence":["scripts/validate.sh"]},{"subject":"claude-desktop-mcpb","status":"not-verified","target":{"kind":"host-session","id":"not-run"},"reason":"desktop session unavailable"}]}'

OVERCLAIM="$TMP/overclaim.json"
write "$OVERCLAIM" '{"schemaVersion":1,"release":{"version":"0.8.0"},"records":[{"subject":"codex-desktop","status":"host-verified","target":{"kind":"source-checkout","id":"commit:abc"},"observedAt":"2026-09-05T14:00:00Z","evidence":["scripts/validate.sh"]}]}'

PARALLEL="$TMP/parallel.json"
write "$PARALLEL" '{"schemaVersion":1,"release":{"version":"0.8.0"},"records":[{"subject":"codex-cli","status":"source-verified","target":{"kind":"source-checkout","id":"commit:abc"},"observedAt":"2026-09-05T14:00:00Z","evidence":["scripts/validate.sh"],"capabilities":["automatic-parallel-execution"]}]}'

MISSING_TARGET="$TMP/missing-target.json"
write "$MISSING_TARGET" '{"schemaVersion":1,"release":{"version":"0.8.0"},"records":[{"subject":"gitlab-project","status":"project-verified","observedAt":"2026-09-05T14:00:00Z","evidence":["run:1"]}]}'

if python3 "$VALIDATOR" validate "$VALID" >/dev/null 2>&1; then
  ok "正：同等级 source 与 not-verified 记录通过"
else
  bad "正：同等级 source 与 not-verified 记录通过"
fi
if ! python3 "$VALIDATOR" validate "$OVERCLAIM" >/dev/null 2>&1; then
  ok "反：源码不能冒充真实宿主证据"
else
  bad "反：源码不能冒充真实宿主证据"
fi
if ! python3 "$VALIDATOR" validate "$PARALLEL" >/dev/null 2>&1; then
  ok "反：暂停的自动并行能力不能被声明为可用"
else
  bad "反：暂停的自动并行能力不能被声明为可用"
fi
if ! python3 "$VALIDATOR" validate "$MISSING_TARGET" >/dev/null 2>&1; then
  ok "反：项目证据缺少目标身份被拒绝"
else
  bad "反：项目证据缺少目标身份被拒绝"
fi
if [ -f "$GUIDE" ] && python3 - "$GUIDE" <<'PY'
import sys
guide = open(sys.argv[1], encoding="utf-8").read()
for value in ("Codex CLI", "Codex 桌面", "Claude Code CLI", "Claude Code 桌面模式", "Claude Desktop MCPB", "not-verified", "自动并行执行不在支持范围内"):
    assert value in guide, value
PY
then
  ok "正：发布矩阵单列各宿主且声明未验证边界"
else
  bad "正：发布矩阵单列各宿主且声明未验证边界"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
