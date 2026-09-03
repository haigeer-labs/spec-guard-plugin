# Spec: parallel-subagent-preflight

## Objective

在 Codex 中安全复用原生子智能体能力：仅当用户明确确认、`parallel-safety-gate` 报告
`manual-parallel-eligible`，且当前运行时提供原生子智能体工具时，父会话才为候选模块
创建只读预检子智能体，并等待、汇总其结果。

这不是并行代码开发功能。子智能体共享父会话工作目录，不能获得独立 Git worktree；因此
任何代码编辑、测试写入、提交、推送、创建/删除 worktree、分支、Issue、PR、或修改
`.agent/state.json` 都不属于预检范围。

## User Flow

1. 用户先显式运行 readiness、safety gate，必要时确认 `--refresh`。
2. 仅当 safety gate 对候选组返回 `manual-parallel-eligible` 时，Skill 展示模块、精确
   基线 SHA、共享工作目录限制和“只读预检”范围。
3. 父会话必须获得用户明确确认后，才调用原生 `spawn_agent`；每个任务名使用
   `sg-preflight-<module-id>`，提示首行使用 `SG 自动并行预检｜<module-id>`。
4. 每个子智能体只审查自己的模块 spec、Parallel Boundary、依赖、实施风险和测试范围；
   输出结构化简报，不修改项目。
5. 父会话等待所有子智能体，统一报告分歧、阻塞项和下一步。通过预检不等于授权并行写入。

## Host Behaviour

- Codex：在当前父会话的原生子智能体工具可用时执行上述只读预检；父会话负责等待、
  汇总和关闭。
- Claude 或无法使用子智能体的 Codex 会话：不模拟子智能体、不创建顶层任务；报告
  降级原因，并返回既有 `parallel-guidance` 的人工 worktree 指引。

## Boundaries

- Always: 复用 safety gate 的分类、证据、模块顺序与 SHA；显式说明共享工作目录和
  用户确认；要求子智能体只读。
- Ask first: 每一次调用 `spawn_agent`，以及任何 `--refresh`。
- Never: 自动写代码、并发写入、调用 `git worktree`/`git branch`/`git merge`/`git push`，
  或创建、更新、归档、删除宿主任务、Issue、PR 和 state。

## Success Criteria

1. 合格组只在明确确认后才产生原生、可在父会话查看的子智能体。
2. 每个子智能体的任务名与提示都能识别其为 SG 自动预检及所属模块。
3. 没有原生子智能体能力时稳定降级为人工指引。
4. 测试证明该 Skill 不会承诺 worktree 隔离或自动并行写入。
