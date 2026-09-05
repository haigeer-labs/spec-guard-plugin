# Spec: parallel-workflow-integration

## Objective

把既有只读分析结果连接到显式确认的并行执行生命周期，同时不破坏普通 Spec Guard 项目的
`/next`、`/deliver`、单 `activeModule` 和模块级 PR 契约。

## Tech Stack

- Markdown commands / skills：Codex 与 Claude 的交互入口。
- Python 3 控制器 CLI：调用 ledger、runtime 与 CLI adapter。
- 既有 GitHub/GitLab bridge：仍是 tracker 事实源，不作为并发锁。

## Commands

```text
/parallel-execute                 # 仅在用户确认且 safety gate 合格后创建 run
/parallel-status <run-id>         # 只读汇总 worker、lease、验证和可汇合状态
/parallel-integrate <run-id> <module-id>  # 每次只处理一个模块，需用户确认
/parallel-reclaim <run-id> <worker-id>    # owned worker 的确认式回收
```

## Interface Contract

`/parallel-execute` 必须消费本次安全门报告的 base SHA、候选 module 和边界，不得仅凭旧文本
报告或 `manual-parallel-eligible` 字样启动。它要求一次明确用户确认，并为每个 module 取得
独立 lease；任何一个候选无法 provision 时不得让该模块写入，其他 module 的状态必须清晰可见。

有效 manifest 存在时，worker `/next` 与 `/deliver` 只允许处理 manifest 指定 module，不能推进
`activeModule`、关闭 initiative 或自行汇合。没有有效 manifest 的普通项目完全保持既有行为。
`/parallel-integrate` 每次合并一个模块，重新验证默认分支后再处理下一个；不自动 merge。

## Project Structure

```text
plugins/spec-guard/commands/parallel-execute.md
plugins/spec-guard/commands/parallel-status.md
plugins/spec-guard/commands/parallel-integrate.md
plugins/spec-guard/commands/parallel-reclaim.md
plugins/spec-guard/skills/spec-guard-ops/SKILL.md
plugins/spec-guard/commands/next.md
plugins/spec-guard/commands/deliver.md
plugins/spec-guard/hooks/test-parallel-workflow-integration.sh
```

## Testing Strategy

- 没有确认、无 safety report、基线不一致或 lease 冲突均不执行写操作。
- 普通 `/next`、`/deliver` 回归保持原输出与 tracker 路由。
- worker 模式只能获取本模块 task；不能移动 canonical activeModule。
- 每次 integrate 都要求确认，失败后不会标记后续模块已汇合。

## Boundaries

- Always: 保持现有只读并行命令只读；在执行前展示 run、module、base 与所有权。
- Ask first: 创建 run、启动 worker、任何 merge/PR/MR 操作、discard/reclaim。
- Never: 隐式升级 `parallel-guidance` 或 preflight 为写 worker；批量自动合并；修改 tracker 作为锁。

## Success Criteria

1. 普通单模块流程无行为回归。
2. worker 模式不可能通过 `/next` 或 `/deliver` 越出受分配 module。
3. 创建、汇合和回收均有明确确认与可审计状态。

## Parallel Boundary

```json
{
  "paths": ["plugins/spec-guard/commands/parallel-execute.md", "plugins/spec-guard/commands/parallel-status.md", "plugins/spec-guard/commands/parallel-integrate.md", "plugins/spec-guard/commands/parallel-reclaim.md", "plugins/spec-guard/skills/spec-guard-ops/SKILL.md", "plugins/spec-guard/commands/next.md", "plugins/spec-guard/commands/deliver.md", "plugins/spec-guard/hooks/test-parallel-workflow-integration.sh"],
  "publicInterfaces": ["parallel-execute-command-v1", "parallel-worker-workflow-v1"],
  "migrations": [],
  "globalConfig": [],
  "testResources": []
}
```
