#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT/scripts/release-evidence.py"
GUIDE="$ROOT/docs/releases/README.md"
JOURNEY_GUIDE="$ROOT/docs/releases/acceptance-journeys.md"
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

JOURNEY="$TMP/journey.json"
write "$JOURNEY" '{"schemaVersion":1,"release":{"version":"0.8.0"},"records":[{"subject":"codex-cli","status":"source-verified","target":{"kind":"source-checkout","id":"commit:abc"},"observedAt":"2026-09-05T14:00:00Z","evidence":["scripts/validate.sh"]}],"journeys":[{"id":"github-first-use","kind":"github-project","confirmation":"required","status":"not-verified","target":{"kind":"tracker-project","id":"github.com/example/spec-guard-e2e"},"expectedSideEffects":["create named test issues"],"reason":"requires explicit project approval"}]}'

UNCONFIRMED_JOURNEY="$TMP/unconfirmed-journey.json"
write "$UNCONFIRMED_JOURNEY" '{"schemaVersion":1,"release":{"version":"0.8.0"},"records":[{"subject":"codex-cli","status":"source-verified","target":{"kind":"source-checkout","id":"commit:abc"},"observedAt":"2026-09-05T14:00:00Z","evidence":["scripts/validate.sh"]}],"journeys":[{"id":"github-first-use","kind":"github-project","confirmation":"not-required","status":"not-verified","target":{"kind":"tracker-project","id":"github.com/example/spec-guard-e2e"},"expectedSideEffects":["create named test issues"],"reason":"requires explicit project approval"}]}'

WRONG_JOURNEY_TARGET="$TMP/wrong-journey-target.json"
write "$WRONG_JOURNEY_TARGET" '{"schemaVersion":1,"release":{"version":"0.8.0"},"records":[{"subject":"codex-cli","status":"source-verified","target":{"kind":"source-checkout","id":"commit:abc"},"observedAt":"2026-09-05T14:00:00Z","evidence":["scripts/validate.sh"]}],"journeys":[{"id":"github-first-use","kind":"github-project","confirmation":"required","status":"not-verified","target":{"kind":"source-checkout","id":"commit:abc"},"expectedSideEffects":["create named test issues"],"reason":"requires explicit project approval"}]}'

DEGRADED_AS_VERIFIED="$TMP/degraded-as-verified.json"
write "$DEGRADED_AS_VERIFIED" '{"schemaVersion":1,"release":{"version":"0.8.0"},"records":[{"subject":"codex-cli","status":"source-verified","target":{"kind":"source-checkout","id":"commit:abc"},"observedAt":"2026-09-05T14:00:00Z","evidence":["scripts/validate.sh"]}],"journeys":[{"id":"offline","kind":"degraded-environment","confirmation":"required","target":{"kind":"environment","id":"offline"},"expectedSideEffects":["make no external writes"],"observedAt":"2026-09-05T14:00:00Z","evidence":["command:offline"]}]}'

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
if python3 "$VALIDATOR" validate "$JOURNEY" >/dev/null 2>&1; then
  ok "正：待确认的真实验收旅程可被如实记录"
else
  bad "正：待确认的真实验收旅程可被如实记录"
fi
if ! python3 "$VALIDATOR" validate "$UNCONFIRMED_JOURNEY" >/dev/null 2>&1; then
  ok "反：未要求确认的真实验收旅程被拒绝"
else
  bad "反：未要求确认的真实验收旅程被拒绝"
fi
if ! python3 "$VALIDATOR" validate "$WRONG_JOURNEY_TARGET" >/dev/null 2>&1; then
  ok "反：项目旅程不能把源码冒充为目标"
else
  bad "反：项目旅程不能把源码冒充为目标"
fi
if ! python3 "$VALIDATOR" validate "$DEGRADED_AS_VERIFIED" >/dev/null 2>&1; then
  ok "反：降级环境不能伪造为已验证旅程"
else
  bad "反：降级环境不能伪造为已验证旅程"
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
if [ -f "$JOURNEY_GUIDE" ] && python3 - "$JOURNEY_GUIDE" <<'PY'
import sys
guide = open(sys.argv[1], encoding="utf-8").read()
for value in ("GitHub 测试仓库", "GitLab 测试仓库", "两个手工创建的不同 worktree", "逐次获得用户确认", "not-verified"):
    assert value in guide, value
PY
then
  ok "正：真实验收旅程明确范围、确认边界与降级结果"
else
  bad "正：真实验收旅程明确范围、确认边界与降级结果"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
