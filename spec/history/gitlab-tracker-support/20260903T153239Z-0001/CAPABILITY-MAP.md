# Capability Map: GitLab Tracker Support

> 由 `/spec` 的 Phase 0 产出。**必须经人工评审后才能往下走。**
> Addy 原文：把图搞错代价很大，评审十行不算什么。

## 目标

让 Spec Guard 在真实 GitLab 项目中提供可执行的任务与交付工作流，同时保持既有 GitHub
行为不变。插件必须自动识别 GitLab、GitHub 与纯本地仓库：GitLab 使用 `glab` 与
GitLab API；GitHub 使用现有 `gh` 工作流；无法确认远端托管平台时采用本地模式。

GitLab 15.3.2 实测范围是 Issue、Issue `relates_to` 链接和 Merge Request；不依赖
该版本缺失的 Work Items、父子 Issue 或阻塞关系语义，并把这些能力差异明确反馈给使用者。

<!-- 这一段是 Epic issue 正文摘要的**唯一来源**，也是它的指纹底本。
     改了这里，phase-guard 会提醒你 Epic 正文过期了（跑 /sync-map 刷新）。
     标题必须是 `## 目标`（或 `## Goal`）—— 指纹脚本按标题定位这一节。 -->

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| tracker-detection | 根据显式配置、远端与已认证 CLI 探测 GitLab、GitHub 或本地模式；探测失败不得误判为另一平台 | — |
| gitlab-workflow | 定义 GitLab Issue、关联和 Merge Request 的命令契约与能力降级；保留可审计的任务映射 | tracker-detection |
| tracker-routing | 让 hook、设置命令和 skills 将 GitHub、GitLab、本地项目路由到相应实现，并保持 GitHub 兼容 | tracker-detection, gitlab-workflow |
| gitlab-e2e | 在 hqdf/web/x9-live-player 上验证自动识别、Issue、MR、清理及降级提示 | tracker-routing |

Build order: tracker-detection → gitlab-workflow → tracker-routing → gitlab-e2e

---

## 评审记录

- [x] 模块边界确认（砍掉或替换一个模块，不需要重写其他模块的需求）
- [x] 依赖方向单向无环（互相依赖 = 它们本来就是一个模块）
- [x] module id 已定稿（kebab-case，之后绝不改名 —— 同一个 id 同时是
      `spec/<id>.md`、`tasks/<id>/`、`state.json`、`feat/<id>` 分支和 issue 标题的名字，
      其中后两处改不动）
- [x] 构建顺序符合依赖拓扑

评审人：用户
日期：2026-09-03
