#!/usr/bin/env bash
# Install the local, file-backed multi-spec convention.  Remote tracker modes
# were retired and deliberately do not have a fallback.
set -euo pipefail

MODE="local"
HOST="claude"
DRY=false
REPLACE=false
for arg in "$@"; do
  case "$arg" in
    local) MODE=local ;;
    github|gitlab)
      echo "${arg} tracker mode was retired; no files were changed." >&2
      exit 2
      ;;
    --host=codex) HOST=codex ;;
    --dry-run) DRY=true ;;
    --replace) REPLACE=true ;;
    *) echo "usage: setup-convention.sh [local] [--host=codex] [--dry-run] [--replace]" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJECT"
ROOT="$(cd "$HERE/.." && pwd)"
if [ "$HOST" = codex ]; then
  TARGET=AGENTS.md
  TEMPLATE="$ROOT/templates/codex-block-local.md"
  BEGIN='<!-- BEGIN:spec-guard-codex-convention -->'
  END='<!-- END:spec-guard-codex-convention -->'
else
  TARGET=CLAUDE.md
  TEMPLATE="$ROOT/templates/claude-block-local.md"
  BEGIN='<!-- BEGIN:agent-skills-convention -->'
  END='<!-- END:agent-skills-convention -->'
fi

install_block() {
  if grep -qF "$BEGIN" "$TARGET" 2>/dev/null; then
    if [ "$REPLACE" != true ]; then
      printf '  ⏭ %s already has a convention block (use --replace to update it)\n' "$TARGET"
      return
    fi
    if [ "$DRY" = true ]; then
      printf '  • replace the convention block in %s\n' "$TARGET"
      return
    fi
    python3 - "$TARGET" "$BEGIN" "$END" "$TEMPLATE" <<'PY'
from pathlib import Path
import sys
target, begin, end, template = sys.argv[1:]
text = Path(target).read_text(encoding="utf-8")
start = text.index(begin) + len(begin)
finish = text.index(end, start)
replacement = "\n" + Path(template).read_text(encoding="utf-8").rstrip() + "\n"
Path(target).write_text(text[:start] + replacement + text[finish:], encoding="utf-8")
PY
    printf '  ✅ updated %s\n' "$TARGET"
    return
  fi
  if [ "$DRY" = true ]; then
    printf '  • append a convention block to %s\n' "$TARGET"
    return
  fi
  [ -f "$TARGET" ] && printf '\n' >> "$TARGET"
  { printf '%s\n' "$BEGIN"; cat "$TEMPLATE"; printf '%s\n' "$END"; } >> "$TARGET"
  printf '  ✅ updated %s\n' "$TARGET"
}

echo '═══ Spec Guard local convention ═══'
if [ "$DRY" = true ]; then
  echo '  • create spec/, tasks/, and .agent/ when absent'
  echo '  • create a local state file only when absent'
else
  mkdir -p spec tasks .agent
  if [ ! -f .agent/state.json ]; then
    printf '%s\n' '{"tracker":"none","modules":{},"activeModule":""}' > .agent/state.json
    echo '  ✅ created .agent/state.json (local only)'
  else
    echo '  ⏭ .agent/state.json already exists; it was not changed'
  fi
  if [ ! -f spec/CAPABILITY-MAP.md ]; then
    cp "$ROOT/templates/CAPABILITY-MAP.md" spec/CAPABILITY-MAP.md
    echo '  ✅ created spec/CAPABILITY-MAP.md'
  else
    echo '  ⏭ spec/CAPABILITY-MAP.md already exists'
  fi
fi
install_block

if [ "$DRY" = true ]; then
  echo '（dry-run; no files were changed）'
else
  echo 'Next: review the capability map, then write module specs and local task lists.'
fi
