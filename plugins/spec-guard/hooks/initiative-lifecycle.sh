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
  pause|resume|complete|abandon|supersede) ;;
  *) echo "用法: initiative-lifecycle.sh <pause|resume|complete|abandon|supersede> --project <path> --initiative <id> [--dry-run]" >&2; exit 2 ;;
esac
EVENT_TYPE="$ACTION"
[ "$ACTION" = pause ] && EVENT_TYPE=paused
[ "$ACTION" = complete ] && EVENT_TYPE=completed
[ "$ACTION" = abandon ] && EVENT_TYPE=abandoned
[ "$ACTION" = supersede ] && EVENT_TYPE=superseded
[ -n "$PROJECT" ] && [ -n "$INITIATIVE" ] || { echo "必须指定项目和 initiative" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd -P)" || { echo "项目目录不存在或不可访问" >&2; exit 2; }
case "$INITIATIVE" in
  *[!a-z0-9-]*|''|-*|*-|*--*) echo "initiative 必须是 kebab-case 标识符" >&2; exit 2 ;;
esac
HISTORY="$(cd "$(dirname "$0")" && pwd)/capability-history.py"
LEDGER="$PROJECT/spec/CAPABILITY-HISTORY.json"
LEDGER_EXISTED=false
[ -e "$LEDGER" ] && LEDGER_EXISTED=true

if [ "$DRY" = true ]; then
  echo "将执行 ${ACTION} initiative=${INITIATIVE}；当前产物不会被修改。"
  exit 0
fi

if [ "$ACTION" = resume ]; then
  [ -f "$LEDGER" ] || { echo "缺少 spec/CAPABILITY-HISTORY.json；无法恢复未归档的 initiative。" >&2; exit 1; }
  if [ -e "$PROJECT/spec/CAPABILITY-MAP.md" ] || [ -e "$PROJECT/.agent/state.json" ]; then
    [ -f "$PROJECT/spec/CAPABILITY-MAP.md" ] && [ -f "$PROJECT/.agent/state.json" ] || { echo "当前工作区不完整，无法暂停后恢复" >&2; exit 1; }
    ACTIVE="$(python3 "$HISTORY" active "$LEDGER")" || exit 1
    [ "$ACTIVE" != "$INITIATIVE" ] || { echo "目标 initiative 已是当前工作区" >&2; exit 1; }
    "$0" pause --project "$PROJECT" --initiative "$ACTIVE" || exit 1
  fi
  python3 "$HISTORY" verify-checkpoint "$LEDGER" "$PROJECT" "$INITIATIVE" >/dev/null || exit 1
  CHECKPOINT_JSON="$(mktemp)"
  STAGE="$(mktemp -d "$PROJECT/.initiative-resume.XXXXXX")"
  trap 'rm -f "$CHECKPOINT_JSON"; rm -rf "$STAGE"' EXIT
  python3 "$HISTORY" checkpoint "$LEDGER" "$INITIATIVE" > "$CHECKPOINT_JSON" || exit 1

  while IFS=$'\t' read -r SOURCE TARGET; do
    [ -n "$SOURCE" ] && [ -n "$TARGET" ] || { echo "checkpoint 缺少 state 或产物" >&2; exit 1; }
    [ ! -e "$PROJECT/$TARGET" ] || { echo "恢复目标已存在: $TARGET" >&2; exit 1; }
    mkdir -p "$(dirname "$STAGE/$TARGET")" || exit 1
    cp "$PROJECT/$SOURCE" "$STAGE/$TARGET" || exit 1
  done < <(python3 - "$CHECKPOINT_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    checkpoint = json.load(handle)
state = checkpoint.get("state")
if not state:
    sys.exit(1)
print("%s\t.agent/state.json" % state["path"])
print("%s\tspec/CAPABILITY-MAP.md" % checkpoint["map"]["path"])
for module in checkpoint["modules"]:
    if module.get("spec"):
        print("%s\tspec/%s.md" % (module["spec"]["path"], module["id"]))
    if module.get("plan"):
        print("%s\ttasks/%s/plan.md" % (module["plan"]["path"], module["id"]))
PY
)

  RESTORED="$STAGE/restored"
  : > "$RESTORED"
  while IFS= read -r TARGET; do
    mkdir -p "$(dirname "$PROJECT/$TARGET")" || exit 1
    cp "$STAGE/$TARGET" "$PROJECT/$TARGET" || {
      while IFS= read -r CREATED; do rm -f "$PROJECT/$CREATED"; done < "$RESTORED"
      exit 1
    }
    printf '%s\n' "$TARGET" >> "$RESTORED"
  done < <(find "$STAGE" -type f ! -name restored -print | sed "s|$STAGE/||")

  EVENT="$(mktemp)"
  python3 -c 'import json,sys; json.dump({"type":"resumed","at":"now"}, open(sys.argv[1], "w"))' "$EVENT" || exit 1
  if ! python3 "$HISTORY" append "$LEDGER" "$INITIATIVE" "$EVENT"; then
    while IFS= read -r CREATED; do rm -f "$PROJECT/$CREATED"; done < "$RESTORED"
    rm -f "$EVENT"
    exit 1
  fi
  rm -f "$EVENT"
  echo "已恢复 initiative=$INITIATIVE"
  exit 0
fi

[ -f "$PROJECT/spec/CAPABILITY-MAP.md" ] || { echo "缺少当前能力图" >&2; exit 1; }
[ -f "$PROJECT/.agent/state.json" ] || { echo "缺少当前状态" >&2; exit 1; }

# 本地验证阶段是显式、受限的上下文；未知或不完整的阶段绝不能被 lifecycle
# 当成普通 tracker 状态归档，否则错误 state 会被搬进 history、当前文件也被删掉。
LOCAL_VALIDATION="$(cd "$(dirname "$0")" && pwd)/local_validation.py"
LOCAL_STAGE="$(python3 "$LOCAL_VALIDATION" "$PROJECT" 2>/dev/null || true)"
case "${LOCAL_STAGE%%|*}" in
  invalid)
    echo "本地验证阶段不可用：${LOCAL_STAGE#*|}" >&2
    exit 1
    ;;
  valid|absent) ;;
  *)
    echo "本地验证阶段无法判定；拒绝修改当前产物" >&2
    exit 1
    ;;
esac

# Resolve the copy/cleanup set once from the authoritative capability map.
# State is a projection and may omit local modules, but it may never invent a
# module: using arbitrary state keys here would turn a malformed key into an
# archive or cleanup path.
MODULES=$(python3 - "$PROJECT" "$(dirname "$HISTORY")" <<'PYMODULES'
import json, re, sys
from pathlib import Path
sys.path.insert(0, sys.argv[2])
from capability_map import parse_map
root = Path(sys.argv[1])
state = json.loads((root / '.agent/state.json').read_text())
modules = state.get('modules', {})
if not isinstance(modules, dict):
    raise SystemExit('state.modules 必须是对象')
ids = parse_map(root / 'spec/CAPABILITY-MAP.md', validate_graph=False).order
if any(not re.match(r'^[a-z0-9]+(?:-[a-z0-9]+)*$', module_id) for module_id in ids):
    raise SystemExit('能力图含无效 module id')
if not ids and modules:
    raise SystemExit('能力图没有模块，不能接受 state.modules')
unknown = sorted(set(modules) - set(ids))
if unknown:
    raise SystemExit('state 含能力图中不存在的 module: %s' % ', '.join(unknown))
print('\n'.join(ids))
PYMODULES
) || exit 1

CHECKPOINT="$(date -u +%Y%m%dT%H%M%SZ)-0001"
DEST="$PROJECT/spec/history/$INITIATIVE/$CHECKPOINT"
[ ! -e "$DEST" ] || { echo "checkpoint 已存在" >&2; exit 1; }
STATE_DEST="$PROJECT/.agent/history/$INITIATIVE/$CHECKPOINT"
TASK_DEST="$PROJECT/tasks/history/$INITIATIVE/$CHECKPOINT"
ARCHIVE_COMMITTED=false
discard_uncommitted_checkpoint() {
  [ "$ARCHIVE_COMMITTED" = true ] && return
  rm -rf "$DEST" "$STATE_DEST" "$TASK_DEST"
}
restore_current_artifacts() {
  cp "$DEST/CAPABILITY-MAP.md" "$PROJECT/spec/CAPABILITY-MAP.md" || return 1
  cp "$STATE_DEST/state.json" "$PROJECT/.agent/state.json" || return 1
  while IFS= read -r MODULE; do
    [ -n "$MODULE" ] || continue
    if [ -f "$DEST/$MODULE.md" ]; then
      cp "$DEST/$MODULE.md" "$PROJECT/spec/$MODULE.md" || return 1
    fi
    if [ -f "$TASK_DEST/$MODULE/plan.md" ]; then
      mkdir -p "$PROJECT/tasks/$MODULE" || return 1
      cp "$TASK_DEST/$MODULE/plan.md" "$PROJECT/tasks/$MODULE/plan.md" || return 1
    fi
  done <<< "$MODULES"
}
cleanup_current_artifacts() {
  while IFS= read -r MODULE; do
    [ -n "$MODULE" ] || continue
    rm -f "$PROJECT/spec/$MODULE.md" "$PROJECT/tasks/$MODULE/plan.md" || return 1
  done <<< "$MODULES"
  rm -f "$PROJECT/spec/CAPABILITY-MAP.md" "$PROJECT/.agent/state.json"
}
trap 'discard_uncommitted_checkpoint' EXIT
mkdir -p "$DEST" "$STATE_DEST" || exit 1
cp "$PROJECT/spec/CAPABILITY-MAP.md" "$DEST/CAPABILITY-MAP.md" || exit 1
cp "$PROJECT/.agent/state.json" "$STATE_DEST/state.json" || exit 1
MAP_SHA="$(shasum -a 256 "$DEST/CAPABILITY-MAP.md" | awk '{print $1}')"
STATE_SHA="$(shasum -a 256 "$STATE_DEST/state.json" | awk '{print $1}')"
while IFS= read -r MODULE; do
  [ -n "$MODULE" ] || continue
  [ ! -f "$PROJECT/spec/$MODULE.md" ] || cp "$PROJECT/spec/$MODULE.md" "$DEST/$MODULE.md" || exit 1
  if [ -f "$PROJECT/tasks/$MODULE/plan.md" ]; then
    mkdir -p "$PROJECT/tasks/history/$INITIATIVE/$CHECKPOINT/$MODULE" || exit 1
    cp "$PROJECT/tasks/$MODULE/plan.md" "$PROJECT/tasks/history/$INITIATIVE/$CHECKPOINT/$MODULE/plan.md" || exit 1
  fi
done <<< "$MODULES"
EVENT="$(mktemp)"
trap 'rm -f "$EVENT"' EXIT
python3 - "$EVENT" "$EVENT_TYPE" "$PROJECT" "$INITIATIVE" "$CHECKPOINT" "$MAP_SHA" "$STATE_SHA" "$HISTORY" <<'PY' || exit 1
import hashlib
import json
import os
import sys

event_path, event_type, project, initiative, checkpoint_id, map_sha, state_sha, history_path = sys.argv[1:]
sys.path.insert(0, os.path.dirname(history_path))
from capability_map import parse_map

state = json.load(open(os.path.join(project, ".agent", "state.json"), encoding="utf-8"))
map_rows = parse_map(os.path.join(project, "spec", "CAPABILITY-MAP.md"), validate_graph=False).rows
modules = []
for row in map_rows:
    module_id = row.module_id
    module_state = state.get("modules", {}).get(module_id, {})
    spec_path = "spec/history/%s/%s/%s.md" % (initiative, checkpoint_id, module_id)
    plan_path = "tasks/history/%s/%s/%s/plan.md" % (initiative, checkpoint_id, module_id)
    def artifact(path):
        absolute = os.path.join(project, path)
        if not os.path.isfile(absolute):
            return None
        with open(absolute, "rb") as handle:
            sha256 = hashlib.sha256(handle.read()).hexdigest()
        return {"path": path, "sha256": sha256}
    modules.append({
        "id": module_id,
        "responsibility": row.responsibility,
        "dependsOn": row.depends_on,
        "status": "unknown",
        "issue": module_state.get("issue"),
        "spec": artifact(spec_path),
        "plan": artifact(plan_path),
    })
event = {
    "type": event_type,
    "at": "now",
    "checkpoint": {
        "id": checkpoint_id,
        "map": {"path": "spec/history/%s/%s/CAPABILITY-MAP.md" % (initiative, checkpoint_id), "sha256": map_sha},
        "state": {"path": ".agent/history/%s/%s/state.json" % (initiative, checkpoint_id), "sha256": state_sha},
        "modules": modules,
    },
}
json.dump(event, open(event_path, "w", encoding="utf-8"))
PY
# Verify this new checkpoint before recording completion or removing current files.
# Unrelated legacy checkpoints are checked by verify-history, not this operation.
python3 - "$HISTORY" "$EVENT" "$PROJECT" <<'PYVERIFY' || exit 1
import json, runpy, sys
sys.path.insert(0, __import__('os').path.dirname(sys.argv[1]))
history = runpy.run_path(sys.argv[1])
event = json.load(open(sys.argv[2], encoding='utf-8'))
history['verify']({'initiatives': [{'events': [event]}]}, sys.argv[3])
PYVERIFY
CREATED_EVENT="$(mktemp)"
trap 'rm -f "$EVENT" "$CREATED_EVENT"; discard_uncommitted_checkpoint' EXIT
python3 - "$EVENT" "$CREATED_EVENT" "$INITIATIVE" <<'PY' || exit 1
import json
import sys

event_path, created_path, initiative_id = sys.argv[1:]
with open(event_path, encoding="utf-8") as handle:
    event = json.load(handle)
created = dict(event)
created["type"] = "created"
json.dump(
    {"id": initiative_id, "title": initiative_id, "events": [created]},
    open(created_path, "w", encoding="utf-8"),
)
PY
if ! cleanup_current_artifacts; then
  restore_current_artifacts || echo "清理失败且无法完整恢复当前产物" >&2
  echo "清理当前产物失败；未记录 lifecycle 事件" >&2
  exit 1
fi
if ! python3 "$HISTORY" ensure "$LEDGER" "$CREATED_EVENT"; then
  restore_current_artifacts || echo "无法完整恢复当前产物" >&2
  exit 1
fi
rm -f "$CREATED_EVENT"
if ! python3 "$HISTORY" append "$LEDGER" "$INITIATIVE" "$EVENT"; then
  restore_current_artifacts || echo "无法完整恢复当前产物" >&2
  [ "$LEDGER_EXISTED" = true ] || rm -f "$LEDGER"
  exit 1
fi
ARCHIVE_COMMITTED=true
echo "已执行 $ACTION initiative=$INITIATIVE"
