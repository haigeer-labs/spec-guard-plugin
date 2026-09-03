# Capability Map: capability-history

> 由 agent-skills `spec-driven-development` 的 Phase 0 产出。模块边界经人工评审后，
> 才能分别生成 `spec/<module-id>.md` 与 `tasks/<module-id>/plan.md`。

## 目标

为 spec-guard 增加不断档的 initiative 生命周期记录：项目从 initiative 创建、暂停、恢复到
完成或终止，所有模块能力、依赖、Issue、spec 与 plan 都可全局查询和校验。

扩展不能改变上游 agent-skills 或 spec-guard 既有的当前工作区协议：当前图仍是
`spec/CAPABILITY-MAP.md`，当前模块状态仍由 `.agent/state.json` 管理。

## 模块

| Module id | Responsibility | Depends on |
| --- | --- | --- |
| history-ledger | 定义并维护 `spec/CAPABILITY-HISTORY.json`：initiative 生命周期事件、能力图 checkpoint、模块关系和证据索引。 | — |
| initiative-lifecycle | 安全地创建、暂停、恢复、完成、放弃或替代 initiative；每次切换保留可恢复 checkpoint。 | history-ledger |
| history-verification | 校验当前与历史两条产物链，发现 orphan、缺失或被篡改的历史证据，同时避免假阳性。 | history-ledger |
| history-migration | 从旧根目录产物、旧 state 与 Git 历史生成可审阅迁移预览，并保守导入旧记录。 | history-ledger |
| history-workflow-integration | 接入 Claude/Codex 操作入口、`/sync-map` 防线、模板、文档和完整回归；不复制共享业务逻辑。 | initiative-lifecycle, history-verification, history-migration |

Build order: history-ledger → initiative-lifecycle, history-verification, history-migration → history-workflow-integration

---

## 评审记录

- [x] 模块边界确认：账本、生命周期、校验、迁移和宿主接入可以独立验证。
- [x] 依赖方向单向无环。
- [x] module id 已定稿：kebab-case，后续不改名。
- [x] 构建顺序符合依赖拓扑。

评审人：用户确认（Codex 辅助评审）
日期：2026-09-02
