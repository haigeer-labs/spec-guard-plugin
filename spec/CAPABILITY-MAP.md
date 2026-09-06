# Capability Map: Local Workflow Integrity

## 目标

正确表达尚未激活 tracker 的本地工作，区分历史产物与遗漏模块，在串行工作检查点预告下一步。自动并行执行器保持暂停。

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| local-workflow-context | 显式本地上下文、共享阶段判据与 tracker 门禁 | — |
| historical-artifact-consistency | 历史产物归属与本地阶段完整快照 | local-workflow-context |
| workflow-checkpoint-preview | 共享检查点预告与入口接入 | historical-artifact-consistency |

Build order: local-workflow-context → historical-artifact-consistency → workflow-checkpoint-preview

## 评审记录

用户于 2026-09-06 回复“继续”，确认调查报告中的三块串行设计及本地实施范围。无远端操作授权。
