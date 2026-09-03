# Implementation Plan: GitLab Workflow

## Overview

为已识别的 GitLab 项目提供 `glab` Issue、关联与 Merge Request 工作流，并将 GitLab
15.3 不具备的层级和阻塞语义明确降级。

## Architecture Decisions

- 新增 GitLab 专属 skill/命令适配，不改写现有 GitHub bridge。
- Issue 映射保存项目 ID 与 IID；关联一律标示为 `relates_to`，不视为依赖。
- Work Items 不可用时不调用其 API，也不以 label 模拟层级。

## Task List

> Tasks tracked in GitHub Issues #37.

### Tasks

- #43 定义 GitLab bridge 命令与能力降级
- #44 接入 GitLab 平面 Issue 与关联路由（blocked by #43）
- #45 执行 GitLab workflow 真实 E2E 回归（blocked by #44）

## Verification

- `bash scripts/validate.sh`
- `glab issue list --repo hqdf/web/x9-live-player`
- `glab mr list --repo hqdf/web/x9-live-player`

## Risks

| Risk | Mitigation |
|---|---|
| GitLab 15.3 API 缺能力 | 运行时探测并显式降级。 |
| GitHub 逻辑回归 | 保持独立 bridge，回归全量测试。 |
