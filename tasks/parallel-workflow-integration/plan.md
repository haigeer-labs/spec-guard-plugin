# Implementation Plan: parallel-workflow-integration

## Overview

把已验证的并行分析、run、worktree 与 CLI worker 连接成显式确认的命令工作流；不另建
状态机、不把 tracker 当锁，并保持普通 Spec Guard 项目的单模块路径不变。

> Tasks tracked in GitHub Issues #98。

## Architecture Decisions

- 命令只编排现有 `parallel-safety-gate.py`、`parallel-execution.py`、
  `parallel-worktree.py` 与 `parallel-cli.py`；ledger 是唯一运行事实源。
- 所有会创建 run、provision worker、启动 CLI、merge 或 reclaim 的命令都先展示对象和
  base SHA，再取得本次明确确认；命令不自动 merge 或后台重试 unknown worker。
- worker 模式从 `spec-guard/<worker-id>` 分支与已验证 manifest 推导唯一 module；它不能
  改 canonical `.agent/state.json`、推进 initiative 或处理其他 module。

## Dependency Graph

```text
confirmed execute ──> read-only status ──> integrate / reclaim
       └───────────> worker next/deliver guard ────> final checkpoint
```

## Task List

### Phase 1: Execute and observe

- #123 实现 parallel-execute 的确认式 run 创建
- #124 实现 parallel-status 的只读状态汇总（blocked by #123）

### Phase 2: Worker boundaries and lifecycle

- #125 限制 worker 模式下的 next 与 deliver（blocked by #123）
- #126 实现 parallel-integrate 的单模块确认流程（blocked by #124）
- #127 实现 parallel-reclaim 的确认式回收流程（blocked by #124）

### Final checkpoint

- #128 Checkpoint: 验证完整 parallel workflow（blocked by #125, #126, #127）

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| 旧 safety report 被误用 | 每次 execute 重新产出 JSON report，并由 `create-run` 复验 base SHA 和 capability digest。 |
| worker 越界修改 canonical 流程 | `/next`、`/deliver` 先识别并复验 worker manifest；不确定即停止。 |
| unknown worker 被隐式重试 | status 只读呈现；execute 和 reclaim 都拒绝覆盖已有 ledger 记录。 |
| 多模块被批量汇合 | integrate 只接受一个 module，并要求单独确认。 |
