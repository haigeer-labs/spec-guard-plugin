# 路线图真实环境验收记录

## 目的与范围

本记录验证 `/spec-guard:roadmap` 是否能在真实 GitHub 项目中正确展示本地路线，并如实处理不可读取的远端事实。它是功能验收证据，不是 GitHub Actions、GitLab 或正式发布记录。

- 插件基线：已发布的 `v0.11.1`；本次修复候选为 `0.11.2`。
- 隔离测试仓库：[`haigeer-labs/spec-guard-roadmap-e2e-20260913`](https://github.com/haigeer-labs/spec-guard-roadmap-e2e-20260913)（公开）。
- 真实远端事实：测试仓库的 [GitHub Issue #1](https://github.com/haigeer-labs/spec-guard-roadmap-e2e-20260913/issues/1)，状态为 `OPEN`。
- 边界：未读取、创建或修改任何真实 GitLab 项目；GitLab 功能不在本次验收范围内。

## 已验证事实

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| 已登录的本机 shell 直接运行已发布脚本 | 通过 | 读取到 Issue #1 为 `OPEN`、sub-issue 数为 `0`，并正确渲染 `foundation → current-work → follow-up` 的当前模块、直接依赖、直接后继、检查点和下一行动。 |
| `--all` | 通过 | 仅展开活跃能力图的三个模块，没有虚构百分比、ETA 或完成状态。 |
| Codex 受限 shell 运行路线图 | 通过（降级） | 本地路线完整显示；`gh issue view` 实际返回 `error connecting to api.github.com`，远端事实保持未知，不误报 Issue 不存在或完成。 |
| `0.11.2` 修复候选的同一受限 shell | 通过 | 远端降级信息明确为“GitHub API 网络访问不可用；请检查当前 shell 的网络或沙箱权限后重试”。 |

## 结论与限制

路线图的产品职责是提供保守的工作流导航，而非推断 GitHub 项目进度。真实 Issue 可读取时，它展示已验证的远端状态；连接、认证或凭据无法使用时，它保留本地事实并明确标记远端未知。

Codex sandbox 的网络限制属于宿主执行环境，不是 Issue、能力图或路线图解析失败。插件不能自行放宽 sandbox 网络，也不会要求用户粘贴 token 或自动登录。

## 发布后复核

`0.11.2` 已完成发布，下面记录的是发布后的只读复核；它补充而不改写上面的候选验收事实。

| 项目 | 状态 | 证据 |
| --- | --- | --- |
| 合并与 CI | 通过 | [PR #9](https://github.com/haigeer-labs/spec-guard-plugin/pull/9) 已合并至 `main`；[Validate run](https://github.com/haigeer-labs/spec-guard-plugin/actions/runs/34706826718) 的 Ubuntu 与 macOS job 均通过。 |
| Tag 与 Release | 通过 | [`v0.11.2`](https://github.com/haigeer-labs/spec-guard-plugin/releases/tag/v0.11.2) 是公开、非预发布 Release；注释 tag 指向提交 `38b3e3345a4b03b828295ca91d4f057243aef7cf`。 |
| 本机公开安装 | 通过 | Codex Marketplace 固定到 `haigeer-labs/spec-guard-plugin --ref v0.11.2` 后，`spec-guard@spec-guard-marketplace` 显示 `0.11.2`、已安装且启用。 |
| 已安装 hook 脚本 | 通过 | 已安装的 `phase-guard.sh` 在隔离公开测试仓库输出有效 `UserPromptSubmit` JSON，且自报 `spec-guard: v0.11.2`。 |
| 已安装路线图脚本 | 通过 | 同一真实 Issue 在可联网 shell 中显示 `OPEN`；在 Codex 受限 shell 中准确降级为 GitHub API 网络不可用。 |

`evals/codex-plugin-smoke.sh` 在重新安装后没有取得 hook 被宿主实际执行的 transcript，因此按它的定义记录为“环境未就绪”，而不是产品失败。要补齐这项宿主级证据，需要用户在 Codex 新会话的 `/hooks` 审核并信任新安装版本后重跑 smoke。发布、源码、安装、直接 hook 与路线图验证均不依赖该未完成项。

本次复核没有读取、创建或修改任何真实 GitLab 项目。
