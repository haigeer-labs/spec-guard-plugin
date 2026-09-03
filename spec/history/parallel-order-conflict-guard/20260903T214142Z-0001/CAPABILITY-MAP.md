# Capability Map: Parallel Order Conflict Guard

> 由 `/spec` 的 Phase 0 产出。**必须经人工评审后才能往下走。**
> Addy 原文：把图搞错代价很大，评审十行不算什么。

## 目标

让并行安全门识别能力图中“模块声明无依赖、但 Build order 明确串行”的矛盾，
并保守地降级为需要人工审查。这样不会把展示或隐藏的串行约束误推荐成并行开发，
同时保持已明确、无歧义的独立模块仍可进入人工并行预检。

<!-- 这一段是 Epic issue 正文摘要的**唯一来源**，也是它的指纹底本。
     改了这里，phase-guard 会提醒你 Epic 正文过期了（跑 /sync-map 刷新）。
     标题必须是 `## 目标`（或 `## Goal`）—— 指纹脚本按标题定位这一节。 -->

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| parallel-order-conflict-guard | 将显式串行 Build order 与依赖图的矛盾传入 parallel-safety-gate，输出可解释的 needs-review 结果并以回归测试锁定 | — |

Build order: parallel-order-conflict-guard

---

## 评审记录

- [x] 模块边界确认（仅修正安全门的矛盾判定，不修改 worktree、代理或写入流程）
- [x] 依赖方向单向无环（互相依赖 = 它们本来就是一个模块）
- [x] module id 已定稿（kebab-case，之后绝不改名 —— 同一个 id 同时是
      `spec/<id>.md`、`tasks/<id>/`、`state.json`、`feat/<id>` 分支和 issue 标题的名字，
      其中后两处改不动）
- [x] 构建顺序符合依赖拓扑

评审人：用户（对话确认）
日期：2026-09-04
