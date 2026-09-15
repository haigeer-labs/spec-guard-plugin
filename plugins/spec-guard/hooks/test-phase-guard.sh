#!/usr/bin/env bash
set -euo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

empty="$WORK/empty"
mkdir -p "$empty"
[ -z "$(CLAUDE_PROJECT_DIR="$empty" /bin/bash "$HOOKDIR/phase-guard.sh")" ]

local_project="$WORK/local"
mkdir -p "$local_project/spec"
printf '%s\n' '<!-- BEGIN:spec-guard-codex-convention -->' > "$local_project/AGENTS.md"
printf '%s\n' '# Capability Map' '| Module id | Responsibility | Depends on |' '|---|---|---|' '| alpha | x | — |' > "$local_project/spec/CAPABILITY-MAP.md"
touch "$local_project/spec/alpha.md"
LOCAL=$(CLAUDE_PROJECT_DIR="$local_project" /bin/bash "$HOOKDIR/phase-guard.sh")
grep -q '"hookSpecificOutput"' <<<"$LOCAL"
grep -q 'SPECED' <<<"$LOCAL"
if grep -Eqi 'sync-map|spec-github-bridge|spec-gitlab-bridge' <<<"$LOCAL"; then
  echo 'legacy tracker advice leaked into local phase output' >&2
  exit 1
fi

legacy_project="$WORK/legacy"
mkdir -p "$legacy_project/.agent"
printf '%s\n' '{"tracker":"github","modules":{"alpha":{"issue":1}}}' > "$legacy_project/.agent/state.json"
LEGACY=$(CLAUDE_PROJECT_DIR="$legacy_project" /bin/bash "$HOOKDIR/phase-guard.sh")
grep -q 'LEGACY_TRACKER_RETIRED' <<<"$LEGACY"
if grep -Eqi 'sync-map|spec-github-bridge|spec-gitlab-bridge' <<<"$LEGACY"; then
  echo 'legacy migration output exposed a retired callable path' >&2
  exit 1
fi

echo 'phase-guard retirement regression passed'
