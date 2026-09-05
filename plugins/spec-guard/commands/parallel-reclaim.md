---
description: 经确认后回收一个 Spec Guard 自有的并行 worker
argument-hint: "<run-id> <worker-id>"
allowed-tools: Bash, Read, Write
---

这是 controller-owned worker 的确认式清理入口。**没有本次明确确认时绝不改变 worktree、branch 或
manifest。**它每次只处理一个 worker，绝不根据目录名猜测身份。

`$ARGUMENTS` 必须依次给出 run ID 和 worker ID。

若读取到 manifest 的 `owner=host`，输出 host、hostWorkerId、cwd 与“宿主可回收”，立即停止；**不得调用**
`parallel-worktree.py reclaim`、`git worktree remove`、Desktop archive 或任何删除操作。只有
`owner=spec-guard` 才可继续下面的 controller-owned 流程。

## 阶段一：只读预览

先读取 run，证明该 worker 属于一个已领取 module；然后从受控 manifest 读取 module、branch 与 base，
复验 worktree、CLI 终态以及 branch 是否已被当前 controller HEAD 包含：

```bash
set -- $ARGUMENTS
test "$#" = 2 || { echo "需要 <run-id> <worker-id>" >&2; exit 2; }
RUN="$1"
WORKER="$2"
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
OWNER="$(python3 - "$PROJECT" "$WORKER" "${CLAUDE_PLUGIN_ROOT}/hooks" <<'PY'
import json, os, sys
project, worker, hooks = sys.argv[1:]
sys.path.insert(0, hooks)
from parallel_execution_lib import ledger_root
manifest = json.load(open(os.path.join(ledger_root(project), "workers", worker + ".json"), encoding="utf-8"))
print(manifest.get("owner", "unknown"))
PY
)"
if [ "$OWNER" = "host" ]; then
  echo "host-owned worker：宿主可回收；不得调用 controller reclaim" >&2
  exit 1
fi
STATUS="$(python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-execution.py" status --project "$PROJECT" --run "$RUN" --format json)"
printf '%s\n' "$STATUS"
MODULE="$(printf '%s' "$STATUS" | python3 - "$WORKER" <<'PY'
import json, sys
worker_id = sys.argv[1]
status = json.load(sys.stdin)
if not status.get("ok"):
    raise SystemExit(status.get("reason", "run 状态未知"))
matched = [item for item in status.get("modules", []) if item.get("workerId") == worker_id]
if len(matched) != 1 or matched[0].get("state") != "claimed":
    raise SystemExit("目标 worker 不是唯一的 claimed worker")
print(matched[0]["moduleId"])
PY
)"
MANIFEST="$(python3 - "$PROJECT" "$RUN" "$MODULE" "$WORKER" "${CLAUDE_PLUGIN_ROOT}/hooks" <<'PY'
import json, sys
project, run_id, module_id, worker_id, hooks = sys.argv[1:]
sys.path.insert(0, hooks)
from parallel_worktree_lib import load_worker_manifest
manifest = load_worker_manifest(project, worker_id)
if manifest["runId"] != run_id or manifest["moduleId"] != module_id:
    raise SystemExit("worker manifest 与目标 run/module 不匹配")
print(json.dumps({"branch": manifest["branch"], "baseSha": manifest["baseSha"]}, ensure_ascii=False))
PY
)"
BRANCH="$(printf '%s' "$MANIFEST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["branch"])')"
BASE_SHA="$(printf '%s' "$MANIFEST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["baseSha"])')"
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-worktree.py" verify --project "$PROJECT" --worker "$WORKER" --format json
CLI_STATUS="$(python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-cli.py" inspect --project "$PROJECT" --worker "$WORKER" --format json)"
printf '%s\n' "$CLI_STATUS"
printf '%s' "$CLI_STATUS" | python3 -c '
import json, sys
record = json.load(sys.stdin)
if not record.get("ok") or record.get("state") not in ("completed", "failed"):
    raise SystemExit("worker CLI 不是可回收终态")
'
if git -C "$PROJECT" merge-base --is-ancestor "$BRANCH" HEAD; then
  CONDITION="merged"
else
  CONDITION="unmerged"
fi
printf 'target run=%s worker=%s module=%s branch=%s base=%s condition=%s\n' \
  "$RUN" "$WORKER" "$MODULE" "$BRANCH" "$BASE_SHA" "$CONDITION"
```

任何 unknown、损坏 manifest、非 Spec Guard owner、脏 worktree、非终态 CLI 或失败的 runtime 校验都必须
停止。`condition=merged` 只表示 branch 已包含在当前 HEAD；它仍需要本次明确确认。`condition=unmerged`
时，除本次明确确认外，还必须由用户明确说出 **discard** 该 worker；不能把沉默、失败或 timeout 当作
明确 discard。

## 阶段二：确认后清理

只有用户确认阶段一展示的单个 run、worker、module、branch 与 condition 后才继续。先完整重跑阶段一，
确保结果不变；然后只调用受控 runtime 的一个操作：

```bash
# MODE 不可默认；仅在本次确认后由操作方显式设置。
# merged：MODE=merged；unmerged：用户明确 discard 后才可 MODE=discard。
MODE="${MODE:-}"
if [ "$CONDITION" = "merged" ] && [ "$MODE" = "merged" ]; then
  python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-worktree.py" reclaim --project "$PROJECT" --worker "$WORKER" --merged --format json
elif [ "$CONDITION" = "unmerged" ] && [ "$MODE" = "discard" ]; then
  # 仅在用户明确 discard 这个 worker 后设置 MODE=discard。
  python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-worktree.py" reclaim --project "$PROJECT" --worker "$WORKER" --confirm --format json
else
  echo "回收条件或确认模式无效" >&2
  exit 1
fi
```

不得直接运行 Git worktree 删除或强制删 branch；runtime 会再次核验 controller owner、manifest、worktree
清洁度及 merged 条件。成功后仅报告该 worker 的审计结果；不修改 run 里的其他 module，也不启动新的
worker。
