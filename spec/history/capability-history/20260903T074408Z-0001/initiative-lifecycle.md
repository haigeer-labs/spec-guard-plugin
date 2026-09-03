# Spec: initiative-lifecycle

## Objective

提供受确认、可恢复的 initiative 生命周期操作：创建后记录 `created` checkpoint；切换新 initiative 前暂停当前工作；需要时恢复最近暂停点；完成、放弃或替代时生成终态 checkpoint。任何操作失败都不得丢失当前 `spec/`、`tasks/` 或 `.agent/state.json`。

## Tech Stack

- Bash 3.2：确定性的项目文件操作与宿主入口。
- Python 3 标准库：调用唯一的 `capability-history.py` 读写/验证账本。
- Git：保存 checkpoint 文件与账本的可追溯提交。

## Commands

```bash
/bin/bash plugins/spec-guard/hooks/test-initiative-lifecycle.sh
/bin/bash scripts/validate.sh
```

## Project Structure

```text
plugins/spec-guard/hooks/initiative-lifecycle.sh
plugins/spec-guard/hooks/test-initiative-lifecycle.sh
plugins/spec-guard/hooks/capability-history.py
spec/CAPABILITY-MAP.md
spec/<module-id>.md
tasks/<module-id>/plan.md
spec/history/<initiative-id>/<checkpoint-id>/
tasks/history/<initiative-id>/<checkpoint-id>/
```

## Lifecycle Contract

```text
active --pause--> paused --resume--> active
active --complete/abandon/supersede--> terminal
```

- `pause`：先复制当前 map/spec/plan 至新 checkpoint，验证并追加 `paused`；仅成功后清空当前工作区与 state，允许下一 initiative 成为 active。
- `resume`：只能选择最后事件为 `paused` 的 initiative；当前已有 active initiative 时必须先暂停它；验证 checkpoint 后恢复文件与 state，最后追加 `resumed`。
- 终态操作与 `pause` 共用 checkpoint 流程，但追加 `completed`、`abandoned` 或 `superseded`。
- 所有写操作必须先提供 dry-run；真实移动或覆盖必须得到用户确认。

## Testing Strategy

- 暂停 A 后创建 B：A 的 checkpoint 完整，当前路径与 state 不再引用 A。
- 从 A 恢复：A 的 map/spec/plan/state 恢复，账本追加 `resumed`。
- B 活跃时恢复 A：先暂停 B；任何冲突、目标目录已存在或账本写入失败时不删源文件。
- 完成/放弃/替代不得被写为 `paused` 或错误终态。

## Boundaries

- Always: 先 dry-run、先复制和验证、最后删除当前路径；只调用 `capability-history.py` 写账本。
- Ask first: 执行非 dry-run、覆盖当前文件、选择终态、恢复哪个暂停 initiative。
- Never: 直接覆盖 `CAPABILITY-MAP.md`；从文件名猜 initiative；手写第二份 JSON schema。

## Success Criteria

1. 不完成 A 而切换到 B 时，A 可被完整暂停、查询和恢复。
2. 当前工作区始终只有一个 active initiative，仍兼容上游与现有 spec-guard 路径。
3. 每个中断点都有可验证 checkpoint；失败不会制造断档或删除用户产物。
