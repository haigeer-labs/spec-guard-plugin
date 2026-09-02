#!/usr/bin/env bash
# 当前 initiative 的安全生命周期入口。后续切片才会加入实际 checkpoint 复制与恢复。
set -uo pipefail

ACTION="${1:-}"
[ "$#" -gt 0 ] && shift
PROJECT=""
INITIATIVE=""
DRY=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --initiative) INITIATIVE="${2:-}"; shift 2 ;;
    --dry-run) DRY=true; shift ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

case "$ACTION" in
  pause|complete|abandon|supersede) ;;
  *) echo "用法: initiative-lifecycle.sh <pause|complete|abandon|supersede> --project <path> --initiative <id> [--dry-run]" >&2; exit 2 ;;
esac
EVENT_TYPE="$ACTION"
[ "$ACTION" = pause ] && EVENT_TYPE=paused
[ "$ACTION" = complete ] && EVENT_TYPE=completed
[ "$ACTION" = abandon ] && EVENT_TYPE=abandoned
[ "$ACTION" = supersede ] && EVENT_TYPE=superseded
[ -n "$PROJECT" ] && [ -n "$INITIATIVE" ] || { echo "必须指定项目和 initiative" >&2; exit 2; }
[ -f "$PROJECT/spec/CAPABILITY-MAP.md" ] || { echo "缺少当前能力图" >&2; exit 1; }
[ -f "$PROJECT/.agent/state.json" ] || { echo "缺少当前状态" >&2; exit 1; }
HISTORY="$(cd "$(dirname "$0")" && pwd)/capability-history.py"
LEDGER="$PROJECT/spec/CAPABILITY-HISTORY.json"

if [ "$DRY" = true ]; then
  echo "将执行 ${ACTION} initiative=${INITIATIVE}；当前产物不会被修改。"
  exit 0
fi

[ -f "$LEDGER" ] || { echo "缺少 spec/CAPABILITY-HISTORY.json；先创建账本后才能暂停。" >&2; exit 1; }

CHECKPOINT="$(date -u +%Y%m%dT%H%M%SZ)-0001"
DEST="$PROJECT/spec/history/$INITIATIVE/$CHECKPOINT"
[ ! -e "$DEST" ] || { echo "checkpoint 已存在" >&2; exit 1; }
mkdir -p "$DEST" || exit 1
cp "$PROJECT/spec/CAPABILITY-MAP.md" "$DEST/CAPABILITY-MAP.md" || exit 1
SHA="$(shasum -a 256 "$DEST/CAPABILITY-MAP.md" | awk '{print $1}')"
EVENT="$(mktemp)"
trap 'rm -f "$EVENT"' EXIT
python3 -c 'import json,sys; json.dump({"type":sys.argv[1],"at":"now","checkpoint":{"id":sys.argv[2],"map":{"path":sys.argv[3],"sha256":sys.argv[4]},"modules":[]}}, open(sys.argv[5], "w"))' \
  "$EVENT_TYPE" "$CHECKPOINT" "spec/history/$INITIATIVE/$CHECKPOINT/CAPABILITY-MAP.md" "$SHA" "$EVENT" || exit 1
python3 "$HISTORY" append "$LEDGER" "$INITIATIVE" "$EVENT" || exit 1
rm -f "$PROJECT/spec/CAPABILITY-MAP.md" "$PROJECT/.agent/state.json"
echo "已执行 $ACTION initiative=$INITIATIVE"
