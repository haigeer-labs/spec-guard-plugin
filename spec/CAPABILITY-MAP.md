# Capability Map: Worktree Parallel Execution

> 由 `/spec` 的 Phase 0 产出。模块边界由用户于 2026-09-04 的对话确认。

## 目标

在既有 `parallel-readiness`、`parallel-safety-gate` 与 `parallel-guidance` 已经明确推荐
隔离并行时，为 Spec Guard 增加一个显式确认才启动的 Worktree 执行控制面。它先在 Codex CLI
和 Claude Code CLI 中完成可追溯的隔离 worker、租约、验证、汇合与回收；不改变现有
`.agent/state.json` 的单 `activeModule` 契约，也绝不在共享工作目录中并行写入。

Codex Desktop 与 Claude Code Desktop 仅在原生 Worktree 已由用户创建后登记并验证。Codex
Desktop 当前没有插件可承诺使用的公开 managed-worktree 创建 API，故不把自动创建写入本期范围。

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| parallel-execution-ledger | 在 Git common directory 中维护 run、模块租约、worker manifest、状态恢复和 owned-only cleanup 身份；不修改 `.agent/state.json`。 | — |
| parallel-worktree-runtime | 创建和校验 Git linked worktree、分支、基线、setup 与测试；仅清理由 Spec Guard 创建且 ledger 所有的资源。 | parallel-execution-ledger |
| parallel-cli-execution | 在已验证 worktree 中启动和观察 Codex CLI / Claude Code CLI worker，记录进程结果并在失败时 fail closed。 | parallel-execution-ledger, parallel-worktree-runtime |
| parallel-workflow-integration | 提供 `/parallel-execute`、`/parallel-status`、`/parallel-integrate`、`/parallel-reclaim`，并使 worker 模式下的 `/next`、`/deliver` 只能处理获分配模块。 | parallel-execution-ledger, parallel-cli-execution |
| desktop-worker-registration | 登记、校验和标记用户在 Codex Desktop / Claude Code Desktop 创建的原生 Worktree worker；缺少宿主能力时降级为手工步骤。 | parallel-execution-ledger, parallel-workflow-integration |

Build order: parallel-execution-ledger → parallel-worktree-runtime → parallel-cli-execution → parallel-workflow-integration → desktop-worker-registration

---

## 评审记录

- [x] 模块边界确认（砍掉或替换一个模块，不需要重写其他模块的需求）
- [x] 依赖方向单向无环（互相依赖 = 它们本来就是一个模块）
- [x] module id 已定稿（kebab-case，之后绝不改名）
- [x] 构建顺序符合依赖拓扑

评审人：用户（对话确认）
日期：2026-09-04
