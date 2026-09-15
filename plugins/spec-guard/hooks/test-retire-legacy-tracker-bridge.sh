#!/usr/bin/env bash
# The legacy tracker bridge must be removed from the shipped plugin, not merely
# hidden from a phase suggestion.  Released evidence and retirement documents
# are intentionally outside this assertion.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PLUGIN="$ROOT/plugins/spec-guard"
FAIL=0

missing() {
  if [ -e "$PLUGIN/$1" ]; then
    printf '  ❌ retired surface still shipped: %s\n' "$1"
    FAIL=$((FAIL + 1))
  else
    printf '  ✅ retired surface absent: %s\n' "$1"
  fi
}

absent_from() {
  local needle="$1"
  shift
  if rg -n --glob '!test-retire-legacy-tracker-bridge.sh' "$needle" "$@" >/dev/null 2>&1; then
    printf '  ❌ active shipped surface still references %s\n' "$needle"
    rg -n --glob '!test-retire-legacy-tracker-bridge.sh' "$needle" "$@"
    FAIL=$((FAIL + 1))
  else
    printf '  ✅ active shipped surface has no %s reference\n' "$needle"
  fi
}

echo '═══ legacy tracker bridge retirement ═══'
for path in \
  skills/spec-github-bridge \
  skills/spec-gitlab-bridge \
  commands/sync-map.md \
  commands/next.md \
  commands/deliver.md \
  commands/bind-workspace.md \
  hooks/gitlab-bridge.sh \
  hooks/gitlab_tracker.py \
  hooks/sync-map-gitlab.sh \
  hooks/workspace_binding.py; do
  missing "$path"
done

absent_from 'spec-github-bridge|spec-gitlab-bridge|sync-map-gitlab|gitlab-bridge\.sh|workspace_binding' \
  "$PLUGIN/commands" "$PLUGIN/templates" "$PLUGIN/mcp" "$PLUGIN/hooks/hooks.json"

absent_from 'spec-github-bridge`|spec-gitlab-bridge`|/sync-map' \
  "$ROOT/README.md" "$ROOT/AGENTS.md" "$ROOT/docs/design.md" "$ROOT/docs/maintainer-workflow.md"

absent_from 'spec-github-bridge|spec-gitlab-bridge|sync-map|gitlab_tracker|workspace_binding|\.agent/state\.json' \
  "$PLUGIN/hooks/proposal_contract.py" \
  "$PLUGIN/hooks/proposal_publication.py" \
  "$PLUGIN/hooks/proposal_tracker_read.py" \
  "$PLUGIN/hooks/proposal_review.py" \
  "$PLUGIN/hooks/proposal_promotion_proof.py" \
  "$PLUGIN/hooks/proposal_boundary_guidance.py"

[ "$FAIL" -eq 0 ] || exit 1
printf '  ✅ legacy tracker bridge is absent from the distributed surface\n'
