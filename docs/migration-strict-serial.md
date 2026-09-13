# 严格串行工作流迁移指南

> 适用于下一次包含此破坏性变更的 Spec Guard 发布。它描述的是待发布源码候选，
> 不是已安装的 `v0.11.3` 行为。

Spec Guard 已移除全部 `parallel-*` 命令以及 worker、worktree、lease、边界分析和
汇合运行时。原因是它们需要额外解决资源互斥、状态一致性、失败回收与跨宿主身份等核心
问题，实际收益不足以抵消复杂度。插件现在只支持严格串行的模块推进。

## 受影响的使用者

- 自动化、文档或团队习惯调用任一 `parallel-*` 命令；
- 仍有旧版本会话或人工创建的多 worktree 工作流。

此次迁移不自动改写能力图、不停止旧会话、不删除用户手工创建的 worktree。为兼容上游
`agent-skills` 格式，逗号分组仍被接受，但会按书写顺序串行展开；它不再是并行授权。

## 迁移步骤

1. 在升级前保存当前 worktree 的未提交成果，并确认不会再调用旧版本的 `parallel-*` 命令。
2. 删除脚本、runbook 和 CI 中对以下命令的调用：
   `parallel-readiness`、`parallel-safety-gate`、`parallel-guidance`、`parallel-status`、
   `parallel-execute`、`parallel-integrate`、`parallel-reclaim`、`parallel-register-worker`。
   它们没有一对一替代品；日常推进使用 `roadmap`、`next`、`deliver`，并一次只推进一个模块。
3. 运行项目检查；若能力图仍使用上游的逗号格式，核对展开后的左到右顺序符合团队预期：

   ```bash
   /spec-guard:roadmap
   /spec-guard:verify-artifacts
   /bin/bash scripts/validate.sh       # 插件维护者在源码仓库运行
   ```

## 升级与回退

升级后，在新的宿主会话确认已加载目标版本，再开始新的模块推进。已打开的旧宿主会话不会
自动变成新版本，也不会由新版本代为回收它们的运行资源。

如果迁移尚未完成，应保留在先前已安装的版本并暂停新的 workflow 操作；不要混用两个版本
的命令或让一个版本读取另一个版本产生的运行状态。回退应是维护者明确选择的版本操作，
而不是通过恢复已删除的并行运行时来完成。
