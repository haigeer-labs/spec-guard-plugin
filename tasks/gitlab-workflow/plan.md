# Implementation Plan: GitLab Workflow

## Overview

为已识别的 GitLab 项目提供 `glab` Issue、关联与 Merge Request 工作流，并将 GitLab
15.3 不具备的层级和阻塞语义明确降级。

## Architecture Decisions

- 新增 GitLab 专属 skill/命令适配，不改写现有 GitHub bridge。
- Issue 映射保存项目 ID 与 IID；关联一律标示为 `relates_to`，不视为依赖。
- Work Items 不可用时不调用其 API，也不以 label 模拟层级。

## Task List

> Tasks tracked in GitHub Issues #37 after approval.

### Proposed tasks

1. 增加 GitLab bridge skill，定义安全的 `glab` 命令和能力探测。
2. 让 setup/路由入口在 GitLab 中创建平面 Issue 与可审计关联。
3. 用 mGit 项目执行 Issue、关联、MR、清理的真实 E2E 回归。

## Verification

- `bash scripts/validate.sh`
- `glab issue list --repo hqdf/web/x9-live-player`
- `glab mr list --repo hqdf/web/x9-live-player`

## Risks

| Risk | Mitigation |
|---|---|
| GitLab 15.3 API 缺能力 | 运行时探测并显式降级。 |
| GitHub 逻辑回归 | 保持独立 bridge，回归全量测试。 |
