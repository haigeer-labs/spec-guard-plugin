---
description: 经明确确认后创建并行 run 与隔离 worker
allowed-tools: Bash, Read
---

这是写操作入口。**未得到本次明确确认时，绝不创建 run、lease、worktree、branch 或 CLI worker。**

## 阶段一：只读预览

先运行下面命令，生成新的 safety report 并向用户展示 `base.sha`、唯一 eligible group 的全部
module、每个 module 的 `Parallel Boundary` 与任何 warning：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REPORT="$(mktemp)"
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-safety-gate.py" --project "$PROJECT" --format json > "$REPORT"
python3 - "$REPORT" <<'PY'
import json, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
eligible = [item for item in report["groups"] if item["classification"] == "manual-parallel-eligible"]
if len(eligible) != 1:
    raise SystemExit("没有唯一的 manual-parallel-eligible 候选组")
print(json.dumps({"base": report["base"], "modules": eligible[0]["modules"],
                  "warnings": report.get("warnings", [])}, ensure_ascii=False))
PY
rm -f "$REPORT"
```

若 safety gate 失败、没有唯一合格组、用户没有确认，立即停止。不要把旧 report、
`parallel-readiness` 文本或 `parallel-guidance` 输出当作执行授权。

## 阶段二：确认后执行

只有用户明确确认上一步展示的 **base SHA 与 module 列表** 后才执行。执行时重新生成 report；
若 base 或 eligible modules 变化，停止并重新展示、重新确认。

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REPORT="$(mktemp)"
trap 'rm -f "$REPORT"' EXIT
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-safety-gate.py" --project "$PROJECT" --format json > "$REPORT"
RUN_JSON="$(python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-execution.py" create-run --project "$PROJECT" --safety-report "$REPORT" --format json)"
RUN="$(printf '%s' "$RUN_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run"]["runId"])')"
printf '%s\n' "$RUN_JSON"
python3 - "$REPORT" <<'PY' | while IFS= read -r MODULE; do
import json, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
eligible = [item for item in report["groups"] if item["classification"] == "manual-parallel-eligible"]
if len(eligible) != 1:
    raise SystemExit("eligible group 在确认后变化")
print("\n".join(eligible[0]["modules"]))
PY
  python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-worktree.py" provision --project "$PROJECT" --run "$RUN" --module "$MODULE" --format json
done
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-execution.py" status --project "$PROJECT" --run "$RUN" --format json
```

任一 module provision 失败时，保留已创建的 run 和成功 worker 的 ledger 状态以供后续状态命令
人工处置；不得换共享目录执行、不得重试 unknown worker。此命令不启动
交互式 Codex/Claude CLI；启动每个 worker 仍需用户对指定 host 的单独确认。
