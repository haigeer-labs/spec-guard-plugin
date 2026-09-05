---
description: 审计历史证据，或在明确确认后追加历史补正记录
argument-hint: "audit | correct --confirm <audit-report.json> <correction.json>"
allowed-tools: Bash, Read
---

先运行只读审计；它只输出 JSON 报告，绝不修改账本、checkpoint 或当前 state：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LEDGER="$PROJECT/spec/CAPABILITY-HISTORY.json"
[ -f "$LEDGER" ] || { echo "未验证：没有 capability history ledger"; exit 0; }
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/capability-history.py" audit "$LEDGER" "$PROJECT"
```

审计报告中的 `unknown` 不是失败时可以猜测补齐的值。它表示现有证据无法支撑历史主张；
不要从当前 `activeModule`、文件名或当前时间推断责任、依赖、状态或历史时间。

`correct` 是写操作。只有用户明确确认该次补正后，才允许调用；它会向账本追加
`history-correction` 记录，绝不重写 checkpoint。`<audit-report.json>` 和
`<correction.json>` 必须是用户审阅过的文件，补正必须包含原值、修正值、审计报告哈希、
审计时间、`initiativeId`、`eventIndex`、对应的 `checkpointId`（无 checkpoint 时为
`null`）与 audit finding：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/capability-history.py" correct --confirm \
  "$PROJECT/spec/CAPABILITY-HISTORY.json" <audit-report.json> <correction.json>
```

没有 `--confirm`、审计报告哈希不匹配、证据矛盾，或把 `unknown` 升级成
`completed` 的请求都会被拒绝，且不会写入。
