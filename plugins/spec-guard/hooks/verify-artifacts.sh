#!/usr/bin/env bash
# Read-only structural validation. Remote tracker projection was retired.
set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 2
FAIL=0
WARN=0
PASS=0

ok() { printf '  ✅ %s\n' "$1"; PASS=$((PASS + 1)); }
warn() { printf '  ⚠️  %s\n' "$1"; WARN=$((WARN + 1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL + 1)); }

if [ ! -f spec/CAPABILITY-MAP.md ]; then
  warn 'spec/CAPABILITY-MAP.md 不存在；单模块项目可忽略'
else
  ok '能力图存在'
fi

STRAY=""
for file in SPEC*.md; do
  [ -e "$file" ] || continue
  STRAY="${STRAY}${STRAY:+、}${file}"
done
if [ -n "$STRAY" ]; then
  bad "根目录有不受支持的 spec 文件: ${STRAY}"
else
  ok '没有根目录 spec 漂移'
fi

if [ -f spec/CAPABILITY-MAP.md ]; then
  MAP_IDS=$(python3 - spec/CAPABILITY-MAP.md <<'PY' 2>/dev/null || true
import re
import sys
for line in open(sys.argv[1], encoding="utf-8"):
    match = re.match(r"\|\s*([a-z0-9]+(?:-[a-z0-9]+)*)\s*\|", line)
    if match and match.group(1) not in {"module", "module-id"}:
        print(match.group(1))
PY
)
  for file in spec/*.md; do
    [ -e "$file" ] || continue
    name="${file##*/}"; [ "$name" = CAPABILITY-MAP.md ] && continue
    module="${name%.md}"
    if ! printf '%s\n' "$MAP_IDS" | grep -Fx "$module" >/dev/null 2>&1; then
      bad "能力图上没有的模块 spec: ${module}"
    fi
  done
fi

if [ -f .agent/state.json ]; then
  warn '检测到历史状态文件；远端 tracker 映射不会被读取或验证'
fi

printf '\n结果: %s 通过 · %s 警告 · %s 失败\n' "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ]
