#!/usr/bin/env bash
# Read-only guidance for the local multi-spec convention and legacy migration.
set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

has_block() {
  if grep -q '<!-- BEGIN:agent-skills-convention -->' CLAUDE.md 2>/dev/null; then
    return 0
  fi
  grep -q '<!-- BEGIN:spec-guard-codex-convention -->' AGENTS.md 2>/dev/null
}

has_block || [ -f .agent/state.json ] || exit 0

emit() {
  command -v python3 >/dev/null 2>&1 || exit 0
  printf '%s' "$1" | python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": sys.stdin.read(),
}}))
'
}

legacy_tracker() {
  [ -f .agent/state.json ] || return 1
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - .agent/state.json <<'PY'
import json
import sys
try:
    value = json.load(open(sys.argv[1], encoding="utf-8")).get("tracker")
except Exception:
    value = None
raise SystemExit(0 if value in {"github", "gitlab"} else 1)
PY
}

SPECS=0
for spec in spec/*.md; do
  [ -e "$spec" ] || continue
  [ "${spec##*/}" = CAPABILITY-MAP.md ] || SPECS=$((SPECS + 1))
done

if legacy_tracker; then
  emit "## spec-guard migration notice (read-only)

当前阶段: **LEGACY_TRACKER_RETIRED**

- A previous remote-tracker state file is present.
- This release does not read its mappings, contact a tracker, select tasks, or modify local state.

Preserve the file and remote records as history. Complete or close any remaining tracker work with v0.14.0 before upgrading; use the retirement migration guide for the manual path."
  exit 0
fi

if [ ! -f spec/CAPABILITY-MAP.md ]; then
  emit "## spec-guard local workflow

当前阶段: **IDLE**

- Capability map: absent
- Module specs: ${SPECS}

Suggested next step: create and review a capability map before planning."
  exit 0
fi

if [ "$SPECS" -eq 0 ]; then
  emit "## spec-guard local workflow

当前阶段: **MAP_ONLY**

- Capability map: present
- Module specs: absent

Suggested next step: write the first reviewed module spec under `spec/`."
  exit 0
fi

emit "## spec-guard local workflow

当前阶段: **SPECED**

- Capability map: present
- Module specs: ${SPECS}

Suggested next step: create a module plan and its local task list under \`tasks/<module-id>/\`."
