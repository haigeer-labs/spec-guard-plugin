# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.1.0] - 2026-08-26

首个版本。

### 新增

- `phase-guard.sh` —— UserPromptSubmit hook，注入链路状态并检测断链
  - 9 个阶段的状态机（IDLE / MAP_ONLY / SPECED / TRACKED / PLANNED / TASK_CLAIMED / BUILDING / TASK_READY / MODULE_DONE）
  - 三种 tracker 模式：`github` / `none` / `other`
  - `gh` 不可用时自动降级，不误报
  - 未声明约定的仓库静默退出
- `/setup-convention` —— 在项目中落地目录约定
- `/phase` —— 主动查询链路状态
- `/sync-map` `/next` `/deliver` —— GitHub Issue 流程命令
- `spec-github-bridge` skill —— 四个操作的完整流程
- 三份模板：GitHub 模式声明块、本地模式声明块、能力图

### 已知限制

- 任务层自动化只覆盖 `github` 和 `none` 两种模式，GitLab / Jira 仅检测到 plan 层
- 需要 `gh` ≥ 2.94.0（`--type` / `--parent` / `--blocked-by`）

## [0.2.0] - 2026-08-26

### 新增

- `hooks/setup-convention.sh` —— **确定性执行**的安装脚本，`/setup-convention`
  改为调用它而不是让 LLM 逐步解释。写文件的幂等性和安全性不能有非确定性。
- `--dry-run` 支持
- `/teardown-convention` —— 移除项目约定，保留用户的 spec/plan 内容
- 完整的手动安装章节（README），含可直接复制的 CLAUDE.md 声明块原文，
  AI agent 可不依赖命令自行完成安装
- setup 脚本的回归测试（dry-run 零写入 / 不覆盖用户内容 / 幂等）

### 修复

- 测试脚本在 `cd` 到临时目录后相对路径失效，导致误报

### 已知限制（补充）

- `spec-github-bridge` 里的 gh 命令未经端到端实测
- 已启用 + `gh` 网络调用的 hook 耗时未实测（无 gh 环境下为 ~154ms）
- 文案硬编码中文
- Windows 需 WSL 或 Git Bash
