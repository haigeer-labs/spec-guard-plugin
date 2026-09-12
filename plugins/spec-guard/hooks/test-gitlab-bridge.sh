#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
export CLAUDE_PROJECT_DIR="$WORK"
cat > "$WORK/bin/glab" <<'EOF'
#!/usr/bin/env bash
[ -z "${CALLS:-}" ] || printf '%s\n' "$*" >> "$CALLS"
case "$1:$2" in
  repo:view) exit 0 ;;
  mr:merge) n=0; [ -f "$COUNT" ] && n=$(cat "$COUNT"); n=$((n+1)); echo "$n" > "$COUNT"; [ "$n" -eq 1 ] && exit 1; exit 0 ;;
  api:projects/test%2Fproject/merge_requests/7)
    if [ "${MERGE_STATUS:-retry}" = retry ]; then printf '%s\n' '{"state":"opened","merge_status":"can_be_merged","has_conflicts":false}';
    else printf '%s\n' '{"state":"opened","merge_status":"cannot_be_merged","has_conflicts":false}'; fi ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/glab"
if COUNT="$WORK/no-confirm-count" PATH="$WORK/bin:$PATH" /bin/bash "$ROOT/hooks/gitlab-bridge.sh" merge --repo test/project --iid 7 >/dev/null 2>&1; then
  exit 1
fi
[ ! -e "$WORK/no-confirm-count" ]
forbidden_calls="$WORK/forbidden-calls"
if CALLS="$forbidden_calls" PATH="$WORK/bin:$PATH" /bin/bash "$ROOT/hooks/gitlab-bridge.sh" issue --repo test/project --title title --description-file description.md >/dev/null 2>&1 \
  || CALLS="$forbidden_calls" PATH="$WORK/bin:$PATH" /bin/bash "$ROOT/hooks/gitlab-bridge.sh" relate 1 2 3 >/dev/null 2>&1 \
  || CALLS="$forbidden_calls" PATH="$WORK/bin:$PATH" /bin/bash "$ROOT/hooks/gitlab-bridge.sh" mr --repo test/project --source-branch source --target-branch target --title title >/dev/null 2>&1; then
  exit 1
fi
[ ! -e "$forbidden_calls" ]
COUNT="$WORK/count" PATH="$WORK/bin:$PATH" /bin/bash "$ROOT/hooks/gitlab-bridge.sh" merge --confirm --repo test/project --iid 7
[ "$(cat "$WORK/count")" = 2 ]
if COUNT="$WORK/stop-count" MERGE_STATUS=stop PATH="$WORK/bin:$PATH" /bin/bash "$ROOT/hooks/gitlab-bridge.sh" merge --confirm --repo test/project --iid 7 >/dev/null 2>&1; then
  exit 1
fi
[ "$(cat "$WORK/stop-count")" = 1 ]
printf 'gitlab-bridge merge retry regression passed\n'
