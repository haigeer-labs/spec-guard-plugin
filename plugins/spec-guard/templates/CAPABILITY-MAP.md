# Capability Map: [填写 Initiative 名称]

> 由 `/spec` 的 Phase 0 产出。**必须经人工评审后才能往下走。**
> Addy 原文：把图搞错代价很大，评审十行不算什么。

## 目标

[1-3 句话：这个 initiative 要解决什么问题、给谁用。]

<!-- 这一段是 Epic issue 正文摘要的**唯一来源**，也是它的指纹底本。
     改了这里，phase-guard 会提醒你 Epic 正文过期了（跑 /sync-map 刷新）。
     标题必须是 `## 目标`（或 `## Goal`）—— 指纹脚本按标题定位这一节。 -->

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| example-a | 一句话说清这个模块负责什么 | — |
| example-b | ... | example-a |

Build order: example-a → example-b

---

## 评审记录

- [ ] 模块边界确认（砍掉或替换一个模块，不需要重写其他模块的需求）
- [ ] 依赖方向单向无环（互相依赖 = 它们本来就是一个模块）
- [ ] module id 已定稿（kebab-case，之后绝不改名 —— 同一个 id 同时是
      `spec/<id>.md`、`tasks/<id>/`、`state.json`、`feat/<id>` 分支和 issue 标题的名字，
      其中后两处改不动）
- [ ] 构建顺序符合依赖拓扑

评审人：
日期：
