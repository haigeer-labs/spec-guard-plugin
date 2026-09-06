#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
export CLAUDE_PROJECT_DIR="$WORK"
cat > "$WORK/bin/glab" <<'EOF'
#!/usr/bin/env bash
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
COUNT="$WORK/count" PATH="$WORK/bin:$PATH" /bin/bash "$ROOT/hooks/gitlab-bridge.sh" merge --repo test/project --iid 7
[ "$(cat "$WORK/count")" = 2 ]
if COUNT="$WORK/stop-count" MERGE_STATUS=stop PATH="$WORK/bin:$PATH" /bin/bash "$ROOT/hooks/gitlab-bridge.sh" merge --repo test/project --iid 7 >/dev/null 2>&1; then
  exit 1
fi
[ "$(cat "$WORK/stop-count")" = 1 ]
printf 'gitlab-bridge merge retry regression passed\n'
