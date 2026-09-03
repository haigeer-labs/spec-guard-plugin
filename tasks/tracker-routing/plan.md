# Implementation Plan: Tracker Routing

## Task List

> Tasks tracked in GitHub Issues #38.

1. 补 GitLab 初始化与命令路由回归。
2. 修复测试暴露的 GitHub/GitLab/本地输出漂移。
3. 运行完整回归与真实 mGit 验证。

## Verification

- `bash scripts/validate.sh`
- 已安装 Codex 插件在 mGit 项目运行 `setup-convention gitlab --host=codex --dry-run`。
