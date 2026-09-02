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

[ "$ACTION" = pause ] || { echo "用法: initiative-lifecycle.sh pause --project <path> --initiative <id> [--dry-run]" >&2; exit 2; }
[ -n "$PROJECT" ] && [ -n "$INITIATIVE" ] || { echo "必须指定项目和 initiative" >&2; exit 2; }
[ -f "$PROJECT/spec/CAPABILITY-MAP.md" ] || { echo "缺少当前能力图" >&2; exit 1; }
[ -f "$PROJECT/.agent/state.json" ] || { echo "缺少当前状态" >&2; exit 1; }

if [ "$DRY" = true ]; then
  echo "将暂停 initiative=${INITIATIVE}；当前产物不会被修改。"
  exit 0
fi

echo "缺少 spec/CAPABILITY-HISTORY.json；先创建账本后才能暂停。" >&2
exit 1
