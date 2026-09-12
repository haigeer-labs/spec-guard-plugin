# Spec Guard 合并后安全证据

## 目的与范围

本文是 [整体基线审查](2026-09-12-plugin-audit.md) 的合并后补记，记录安全整改在新公开仓库中的可复核证据。它不改写基线中的历史事实，也不构成正式发布记录。

- 目标仓库：[`haigeer-labs/spec-guard-plugin`](https://github.com/haigeer-labs/spec-guard-plugin)
- 审查批次：`codex/audit-safety-remediation`
- 合并请求：[#4](https://github.com/haigeer-labs/spec-guard-plugin/pull/4)
- 合并提交：[`4ccf9ac`](https://github.com/haigeer-labs/spec-guard-plugin/commit/4ccf9ac889c3f4dd78431d401d61732b3ae97459)

## 新增可复核证据

| 证据 | 状态 | 说明 |
| --- | --- | --- |
| PR 验证 | 通过 | [Run #10](https://github.com/haigeer-labs/spec-guard-plugin/actions/runs/34699643705) 对 PR #4 执行了 Ubuntu 与 macOS 两个 job，均通过。 |
| 主分支验证 | 通过 | [Run #11](https://github.com/haigeer-labs/spec-guard-plugin/actions/runs/34700155783) 在合并提交 `4ccf9ac` 上自动触发，Ubuntu job 通过。 |
| CI 策略 | 已验证 | `pull_request` 保留 Ubuntu/macOS 双平台覆盖；`push` 到 `main` 只跑 Ubuntu，避免把 macOS 配额消耗在可由本机覆盖的重复验证上。 |
| 真实 GitLab | 未操作 | 未读取、创建或修改真实 GitLab 项目。所有 GitLab 相关回归继续使用本地 `glab` 桩。 |

## 对问题清单的影响

R10（原账号无法产生 Actions 证据）不再是当前仓库的外部阻塞：迁移到公开组织仓库后，PR 和 `main` 均已产生并通过实际 GitHub Actions 运行。原报告保留该条，是为了如实记录旧账号和旧仓库的历史限制。

R07 与 R09 仍未完全收口：GitLab 仅有本地桩验证，任何真实 GitLab 验收都必须得到用户对**隔离目标项目**的明确授权；当前批次也没有创建命名版本、tag 或正式 release artifact。

## 复评

当前整改后的源码候选评分调整为 **74/100（可作为受控候选，尚不应声明为稳定发布）**：

- 核心问题价值：18/20
- 设计边界：11/20
- 功能闭环：14/20
- 安全与数据完整性：17/20
- 验证与发布可信度：14/20

提升来自独立候选插件 smoke、定向/全量本地回归，以及 PR 的 Ubuntu/macOS 与合并后 `main` 的实际 CI 证据。扣分保留给未命名的发布 artifact、正式安装记录、真实 GitLab 隔离验收，以及仍被明确暂停的并行写能力。

## 发布前最小门槛

1. 建立版本号、tag、release notes 与可复现安装记录。
2. 在用户明确授权的隔离 GitLab 项目中验证 R07；未授权时保持本地桩覆盖，不访问真实 GitLab。
3. 并行写能力继续保持暂停，除非后续独立模块完成真实宿主 E2E、身份、互斥、汇合与回收验收。
