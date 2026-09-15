# Capability Map: Candidate Proposal Pool and Capability Map Promotion

## 目标

让正在实现既有模块的任务能够把新发现的、独立的需求分流到独立设计任务；该需求在合并到远端默认分支后成为可评审 Proposal，并在合适的模块边界被明确评审、再安全晋级到能力图。

这套能力只负责 Proposal、能力图与晋级证据，不调用、不依赖 `spec-github-bridge`，也不接管 Task、分支、PR 或交付流程。`spec-github-bridge` 的退役是后续独立迁移。

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| proposal-contract | 定义并严格校验 Proposal 文档、唯一 Issue marker、阶段标签、能力图基准摘要和受支持变更类型。 | — |
| proposal-publication | 只从远端默认分支读取已发布 Proposal，固定评审 commit，并拒绝把其他 worktree 的本地文件当作共享事实。 | proposal-contract |
| proposal-tracker-read | 用最小的 GitHub/GitLab 只读适配器核验普通 Proposal Issue 的唯一 marker 与唯一阶段，不使用旧 bridge。 | proposal-contract |
| proposal-review | 汇总发布、tracker 与当前能力图事实，给出 ready、stale、blocked 或 unknown 的只读评审结论。 | proposal-publication, proposal-tracker-read |
| proposal-promotion-proof | 对已接受的 new-module Proposal 核验能力图修订已合并、模块/锚点/依赖/构建顺序均已兑现。 | proposal-review |
| proposal-boundary-guidance | 提供 intake/review/晋级核验入口，并仅在模块交付或推进边界给出非阻断的需求池评审提醒。 | proposal-review |

Build order: proposal-contract → proposal-publication → proposal-tracker-read → proposal-review → proposal-promotion-proof → proposal-boundary-guidance

---

## 评审记录

- [x] 模块边界确认（砍掉或替换一个模块，不需要重写其他模块的需求）
- [x] 依赖方向单向无环（互相依赖 = 它们本来就是一个模块）
- [x] module id 已定稿（kebab-case，之后绝不改名 —— 同一个 id 同时是
      `spec/<id>.md`、`tasks/<id>/`、`state.json`、`feat/<id>` 分支和 issue 标题的名字，
      其中后两处改不动）
- [x] 构建顺序符合依赖拓扑

评审人：用户与 Codex
日期：2026-09-15
