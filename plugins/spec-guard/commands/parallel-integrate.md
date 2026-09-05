---
description: 经明确确认后汇合一个已完成的并行 worker
argument-hint: "<run-id> <module-id>"
allowed-tools: Bash, Read, Write
---

这是单模块汇合入口。它每次只处理一个 module，**没有本次明确确认时绝不执行 merge**；不批量
处理 run 中的其他 module，不创建 PR/MR，也不改变 tracker 状态。

`$ARGUMENTS` 必须依次给出 run ID 和 module ID。

## 阶段一：只读预览

先读取 run 状态，确认目标 module 已被领取；随后读取 manifest、复验 worktree 与 CLI 记录，并展示
run、module、worker、branch、base SHA 和当前默认分支 HEAD：

```bash
set -- $ARGUMENTS
test "$#" = 2 || { echo "需要 <run-id> <module-id>" >&2; exit 2; }
RUN="$1"
MODULE="$2"
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATUS="$(python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-execution.py" status --project "$PROJECT" --run "$RUN" --format json)"
printf '%s\n' "$STATUS"
IFS=$'\t' read -r WORKER BASE_SHA < <(printf '%s' "$STATUS" | python3 - "$MODULE" <<'PY'
import json, sys
module_id = sys.argv[1]
status = json.load(sys.stdin)
if not status.get("ok"):
    raise SystemExit(status.get("reason", "run 状态未知"))
matched = [item for item in status.get("modules", []) if item.get("moduleId") == module_id]
if len(matched) != 1 or matched[0].get("state") != "claimed":
    raise SystemExit("目标 module 不是唯一的 claimed worker")
print("%s\t%s" % (matched[0]["workerId"], status["baseSha"]))
PY
)
MANIFEST="$(python3 - "$PROJECT" "$RUN" "$MODULE" "$WORKER" "${CLAUDE_PLUGIN_ROOT}/hooks" <<'PY'
import json, sys
project, run_id, module_id, worker_id, hooks = sys.argv[1:]
sys.path.insert(0, hooks)
from parallel_worktree_lib import load_worker_manifest
manifest = load_worker_manifest(project, worker_id)
if manifest["runId"] != run_id or manifest["moduleId"] != module_id:
    raise SystemExit("worker manifest 与目标 run/module 不匹配")
print(json.dumps({"workerId": worker_id, "branch": manifest["branch"],
                  "baseSha": manifest["baseSha"]}, ensure_ascii=False))
PY
)"
BRANCH="$(printf '%s' "$MANIFEST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["branch"])')"
MANIFEST_BASE="$(printf '%s' "$MANIFEST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["baseSha"])')"
test "$BASE_SHA" = "$MANIFEST_BASE" || { echo "run 与 manifest base SHA 不一致" >&2; exit 1; }
CURRENT_HEAD="$(git -C "$PROJECT" rev-parse HEAD)"
printf 'target run=%s module=%s worker=%s branch=%s base=%s current=%s\n' \
  "$RUN" "$MODULE" "$WORKER" "$BRANCH" "$BASE_SHA" "$CURRENT_HEAD"
test "$BASE_SHA" = "$CURRENT_HEAD" || { echo "base SHA 与当前默认分支 HEAD 不一致" >&2; exit 1; }
test -z "$(git -C "$PROJECT" status --porcelain)" || { echo "默认分支工作区不干净" >&2; exit 1; }
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-worktree.py" verify --project "$PROJECT" --worker "$WORKER" --format json
CLI_STATUS="$(python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-cli.py" inspect --project "$PROJECT" --worker "$WORKER" --format json)"
printf '%s\n' "$CLI_STATUS"
printf '%s' "$CLI_STATUS" | python3 -c '
import json, sys
record = json.load(sys.stdin)
if not record.get("ok") or record.get("state") != "completed":
    raise SystemExit("worker CLI 不是 completed")
'
git -C "$PROJECT" merge-base --is-ancestor "$BASE_SHA" "$BRANCH"
git -C "$PROJECT" diff --check "$BASE_SHA...$BRANCH"
```

任一校验失败、CLI 不是 `completed`、目标 branch 不可达，或用户没有对上述**这个 module**作出本次明确
确认时，立即停止。base SHA 与当前默认分支 HEAD 不一致时，必须新建或人工更新执行上下文；不得隐式
rebase、cherry-pick、切换到共享目录或尝试合并。

## 阶段二：确认后汇合

只有用户确认阶段一展示的 run、module、branch、base SHA 与验证结果后才继续。先完整重跑阶段一；结果
仍一致且默认分支工作区干净时，执行唯一的一次 Git merge：

```bash
git -C "$PROJECT" merge --no-ff "$BRANCH"
```

若 Git 报告冲突，停止并把冲突状态、run、module 与 branch 报告给用户；不得 reset、force 或自动解决。
成功后仅报告这个 module 已汇合，保留 worker manifest 和 run ledger 供后续人工审计与清理。下一个
module 必须重新从本命令的阶段一开始，并获得它自己的明确确认。
