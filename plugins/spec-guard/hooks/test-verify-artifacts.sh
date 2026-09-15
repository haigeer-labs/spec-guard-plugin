#!/usr/bin/env bash
set -euo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/spec"
printf '%s\n' '# Capability Map' '| Module id | Responsibility | Depends on |' '|---|---|---|' '| alpha | x | — |' > "$WORK/spec/CAPABILITY-MAP.md"
touch "$WORK/spec/alpha.md"
CLAUDE_PROJECT_DIR="$WORK" /bin/bash "$HOOKDIR/verify-artifacts.sh" >/dev/null

touch "$WORK/SPEC-alpha.md"
if CLAUDE_PROJECT_DIR="$WORK" /bin/bash "$HOOKDIR/verify-artifacts.sh" >/dev/null; then
  echo 'verify-artifacts accepted a root-level spec' >&2
  exit 1
fi

echo 'verify-artifacts retirement regression passed'
