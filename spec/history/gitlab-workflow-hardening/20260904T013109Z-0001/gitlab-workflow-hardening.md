# Spec: GitLab Workflow Hardening

## Goal

让 GitLab map 同步按能力图 Build order 选择首个 active module、写回 initiative title，
并让 MR 合并遇到首次短暂 422 时只在远端仍为 `can_be_merged` 的情况下复核并重试一次。

## Acceptance criteria

1. 两模块 map 同步后，state 的 `initiative.title` 等于能力图标题，`activeModule` 等于 Build order 首项。
2. 合并首次 422 时，只有 API 报告 opened、无冲突且 `can_be_merged` 才重试一次；其他状态立即失败。
3. 新增确定性回归，并在 mGit GitLab 15.3 复跑 map 同步关键断言。

## Non-goals

- 不增加 GitLab 子 Issue、父子或阻塞关系。
- 不改变 GitHub tracker 行为。
