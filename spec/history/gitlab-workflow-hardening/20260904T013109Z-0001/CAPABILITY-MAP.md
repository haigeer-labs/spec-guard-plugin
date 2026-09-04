# Capability Map: GitLab Workflow Hardening

> 由 `/spec` 的 Phase 0 产出。**必须经人工评审后才能往下走。**
> Addy 原文：把图搞错代价很大，评审十行不算什么。

## 目标

修正真实 GitLab 15.3 E2E 暴露的 state 同步错误，并让 Merge Request 合并在首次出现
短暂 422、但远端仍报告可合并时进行受限状态复核和一次重试。

<!-- 这一段是 Epic issue 正文摘要的**唯一来源**，也是它的指纹底本。
     改了这里，phase-guard 会提醒你 Epic 正文过期了（跑 /sync-map 刷新）。
     标题必须是 `## 目标`（或 `## Goal`）—— 指纹脚本按标题定位这一节。 -->

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| gitlab-workflow-hardening | 修复 GitLab map 同步 state 回写和 MR 合并短暂就绪处理，并以确定性与真实 E2E 回归锁定 | — |

Build order: gitlab-workflow-hardening

---

## 评审记录

- [x] 模块边界确认（只修改 GitLab bridge/state 与其回归）
- [x] 依赖方向单向无环（单模块）
- [x] module id 已定稿（kebab-case，之后绝不改名 —— 同一个 id 同时是
      `spec/<id>.md`、`tasks/<id>/`、`state.json`、`feat/<id>` 分支和 issue 标题的名字，
      其中后两处改不动）
- [x] 构建顺序符合依赖拓扑

评审人：用户（真实 E2E 后确认继续修复）
日期：2026-09-04
