#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/release-package.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok() { printf '  ✅ %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL + 1)); }

make_artifact() {
  local artifact="$1"
  mkdir -p "$artifact/.claude-plugin" "$artifact/plugins/spec-guard/.claude-plugin" "$artifact/plugins/spec-guard/.codex-plugin"
  printf '%s\n' '{"name":"spec-guard-marketplace","plugins":[{"name":"spec-guard","source":"./plugins/spec-guard"}]}' > "$artifact/.claude-plugin/marketplace.json"
  printf '%s\n' '{"name":"spec-guard","version":"0.8.0"}' > "$artifact/plugins/spec-guard/.claude-plugin/plugin.json"
  printf '%s\n' '{"name":"spec-guard","version":"0.8.0"}' > "$artifact/plugins/spec-guard/.codex-plugin/plugin.json"
  printf '%s\n' '{"name":"spec-guard","version":"0.8.0"}' > "$artifact/plugins/spec-guard/manifest.json"
  printf '%s\n' '{"schemaVersion":1,"artifactKind":"spec-guard-plugin","version":"0.8.0","files":[".claude-plugin/marketplace.json","plugins/spec-guard/.claude-plugin/plugin.json","plugins/spec-guard/.codex-plugin/plugin.json","plugins/spec-guard/manifest.json"]}' > "$artifact/ARTIFACT-MANIFEST.json"
}

GOOD="$TMP/good"; make_artifact "$GOOD"
BAD_VERSION="$TMP/bad-version"; make_artifact "$BAD_VERSION"
printf '%s\n' '{"name":"spec-guard","version":"0.7.0"}' > "$BAD_VERSION/plugins/spec-guard/.codex-plugin/plugin.json"
SOURCE="$TMP/source"; make_artifact "$SOURCE"; mkdir "$SOURCE/.git"

if python3 "$CHECK" validate "$GOOD" 0.8.0 >/dev/null 2>&1; then ok "正：命名 artifact 的 manifest 与文件一致"; else bad "正：命名 artifact 的 manifest 与文件一致"; fi
if ! python3 "$CHECK" validate "$BAD_VERSION" 0.8.0 >/dev/null 2>&1; then ok "反：包内版本漂移被拒绝"; else bad "反：包内版本漂移被拒绝"; fi
if ! python3 "$CHECK" validate "$SOURCE" 0.8.0 >/dev/null 2>&1; then ok "反：源码 checkout 不能冒充 artifact"; else bad "反：源码 checkout 不能冒充 artifact"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
