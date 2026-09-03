# Capability Map: Parallel Development Readiness Guidance

> 由 `/spec` 的 Phase 0 产出。**必须经人工评审后才能往下走。**

## 目标

在能力图显示多个模块处于同一依赖层时，Spec Guard 基于拉取后的默认分支快照与
模块声明的改动边界，给出保守的并行开发建议。它只解释是否值得人工启动隔离
worktree/子任务，以及如何安全汇合；绝不自动创建、调度、停止或删除宿主任务，
也不改变现有 `.agent/state.json`、`/next` 或模块级 PR 的单模块契约。

<!-- 这一段是 Epic issue 正文摘要的唯一来源，也是它的指纹底本。 -->

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| parallel-readiness | 读取能力图与默认分支快照，列出图上可同时考虑的候选模块及其可追溯基线 | — |
| parallel-safety-gate | 对候选模块声明的路径、公共接口、迁移、配置与测试资源做保守冲突判定，并在信息不足时拒绝判为安全 | parallel-readiness |
| parallel-guidance | 将判定转成用户确认所需的并行建议、命名、手动 worktree/子任务步骤与汇合验证清单 | parallel-safety-gate |

Build order: parallel-readiness → parallel-safety-gate → parallel-guidance

---

## 评审记录

- [x] 模块边界确认（砍掉或替换一个模块，不需要重写其他模块的需求）
- [x] 依赖方向单向无环（互相依赖 = 它们本来就是一个模块）
- [x] module id 已定稿（kebab-case，之后绝不改名）
- [x] 构建顺序符合依赖拓扑

评审人：用户（对话确认）
日期：2026-09-04
