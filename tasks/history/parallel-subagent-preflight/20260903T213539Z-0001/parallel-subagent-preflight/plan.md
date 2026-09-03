# Implementation Plan: parallel-subagent-preflight

## Overview

在 Codex 专用操作 Skill 中加入一个经用户确认的、只读的原生子智能体预检入口；保持
既有 readiness、safety gate 与人工 worktree guidance 不变。

## Architecture Decisions

- 原生 `spawn_agent` 只用于边界/计划/测试审查，绝不用于并行代码写入。
- 子智能体由父会话管理；插件不调用顶层任务 API，也不管理 worktree 生命周期。
- 缺少原生子智能体工具时显式降级到既有 `parallel-guidance`，不伪造成功。

## Task List

> Tasks tracked in GitHub Issues #81

### Phase 1: Codex operation contract

- #82 Define Codex subagent preflight contract

### Phase 2: Guardrails and documentation

- #83 Add preflight guardrail regression and documentation (blocked by #82)

### Checkpoint

- 子智能体只读预检与人工 worktree 写入路径明确分离。
- 全量校验通过，且没有新增宿主任务或 Git 生命周期调用。

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| 子智能体共享工作目录 | 仅允许只读审查，禁止实现与写入型测试。 |
| 运行时无原生工具 | 明确降级到已有手动 guidance，不创建顶层聊天。 |
| 用户误以为可并行开发 | 在入口、子任务提示和父会话汇总中重复声明预检不授权写入。 |
