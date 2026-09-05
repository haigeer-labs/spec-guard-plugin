---
description: 只读汇总一个并行 run 的 lease、worker 与 CLI 状态
argument-hint: "<run-id>"
allowed-tools: Bash, Read
---

这是只读命令。它**绝不**创建 run、lease、worktree、branch、CLI worker，也不重试、汇合或回收
unknown worker。

若 worker manifest 的 `owner=host`，先展示其 host、hostWorkerId、cwd、branch 与“宿主可回收”状态；
不要把它交给 controller-owned `parallel-worktree.py verify` 或 `parallel-cli.py inspect`，也不要把缺少
controller process record 误报成可自动处置的 unknown。

`$ARGUMENTS` 必须是一个 run ID。先输出 ledger 汇总，再对每个已领取 worker 依次输出 runtime
校验与 CLI process 状态：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
RUN="$ARGUMENTS"
test -n "$RUN" || { echo "需要 run ID" >&2; exit 2; }
STATUS="$(python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-execution.py" status --project "$PROJECT" --run "$RUN" --format json)"
printf '%s\n' "$STATUS"
printf '%s' "$STATUS" | python3 -c '
import json, sys
for module in json.load(sys.stdin).get("modules", []):
    if module.get("state") == "claimed":
        print(module["workerId"])
' | while IFS= read -r WORKER; do
  MANIFEST="$(python3 - "$PROJECT" "$WORKER" "${CLAUDE_PLUGIN_ROOT}/hooks" <<'PY'
import json, os, sys
project, worker, hooks = sys.argv[1:]
sys.path.insert(0, hooks)
from parallel_execution_lib import ledger_root
manifest = json.load(open(os.path.join(ledger_root(project), "workers", worker + ".json"), encoding="utf-8"))
print(json.dumps({key: manifest.get(key) for key in ("owner", "host", "hostWorkerId", "worktreePath", "branch")}, ensure_ascii=False))
PY
  )"
  OWNER="$(printf '%s' "$MANIFEST" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("owner", "unknown"))')"
  if [ "$OWNER" = "host" ]; then
    echo "== worker $WORKER host-owned：宿主可回收 =="
    printf '%s\n' "$MANIFEST"
    continue
  fi
  echo "== worker $WORKER runtime =="
  python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-worktree.py" verify --project "$PROJECT" --worker "$WORKER" --format json || true
  echo "== worker $WORKER process =="
  python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-cli.py" inspect --project "$PROJECT" --worker "$WORKER" --format json || true
done
```

将 `unknown`、失败的 runtime 校验、未终结 process 或缺失记录明确报告给用户。只有
`completed` worker 且后续人工复验通过，才可以由单模块汇合流程处理；此命令本身不改变状态。
