# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.3.0] - 2026-08-26

### 新增

- **`/verify-artifacts`** —— 产物落地校验（只读）。`phase-guard` 回答「现在在哪个
  阶段」，它回答「已经落下的产物对不对」。整套约定从头到尾都是**提示词**，
  软指令必须配硬检测，否则跑歪了没人知道。覆盖 9 类检查：

  | 层 | 检查 |
  |---|---|
  | 能力图 | 模板占位符未填 / 评审未勾选 / module id 非 kebab-case |
  | spec | **文件名 ↔ 能力图 module id 比对** |
  | 目录 | 根目录 `SPEC*.md` / `tasks/` 缺命名空间 / `todo.md` 与 tracker 并存 |
  | plan | tracker 模式下仍是 checklist / 没写 tracker 位置 |
  | GitHub | Epic sub-issue 数 ≠ 模块数 / issue 正文粘贴 spec 全文 / PR 缺 `Closes #n` / 分支 task 不属于 activeModule |

  其中 spec 文件名比对补的是最阴险的一类漂移：`phase-guard.sh:80` 只数
  `spec/*.md` 的**数量**，从不跟能力图比对 module id。能力图写 `identity`、
  模型建了 `spec/user-identity.md`，阶段照样往前推，下游全部静默错位。

- `setup-convention.sh` 增加 **issue types 可用性探测**。`--type Feature/Task`
  依赖 GitHub issue types，这是**组织级功能，个人仓库用不了**。原先只查 gh 版本
  和 `--parent` 参数存在性 —— 这两项在个人仓库上一样全绿，然后 `/sync-map`
  的第一条命令就炸。探测不到时降级为警告，绝不假阻塞。
- `test-verify-artifacts.sh` —— 16 个断言，含「合规项目零误报」和「local 模式的
  checkbox 不误报」两条反向用例

### 修复

- **P0：`setup-convention.sh` 的 github 前置检查有 40% 概率假阻塞。**
  `gh issue create --help | grep -q -- "--parent"` —— `grep -q` 命中即关管道，
  还在输出的 `gh` 吃到 SIGPIPE(141)，`set -o pipefail` 把它传出来，判断为假。
  **实测 30 次里 12 次假阻塞**，且错误信息是误导性的「跑 type -a gh 检查 PATH」。
  改 herestring 后 30/30 稳定。
- 同类问题全仓库扫出并修掉 5 处（`setup-convention.sh` ×2、`phase-guard.sh` ×1、
  `validate.sh` ×1、`test-phase-guard.sh` ×1）。其中 `phase-guard.sh:94` 的
  `find tasks -name todo.md | grep -q .` 会漏报「todo.md 与 tracker 并存」。
- CLAUDE.md 加了这条禁令，`/verify-artifacts` 的实现和测试都不用管道

### 已知限制（补充）

- github 模式需要**组织仓库**，个人仓库请用 local 模式
- `verify-artifacts` 的 GitHub 层仍未经端到端实测（缺可用的组织仓库）

## [0.2.1] - 2026-08-26

### 修复

- **P0：macOS 上 hook 静默崩溃。** `$VAR` 后紧跟全角括号（如
  `"…Closes #$BRANCH_ISSUE）"`）时，macOS 自带的 bash 3.2 会把该字符的首字节
  吃进变量名，配合 `set -u` 直接致命退出。共 7 处：

  | 文件 | 影响 |
  |---|---|
  | `phase-guard.sh` ×2 | 进入 `TASK_READY`（准备开 PR 那一刻）hook 就死，且 hook 失败是静默的 |
  | `setup-convention.sh` ×4 | local 模式安装无声失败，`CLAUDE.md` 声明块根本没写进去 |
  | `validate.sh` ×1 | 缺执行位时的提示语 |

  全部改为 `${VAR}`。

### 新增

- `scripts/check-bash32.py` —— 静态检查这一类多字节解析陷阱，已接入 `validate.sh`
- CI 加 macOS matrix 并显式用 `/bin/bash` —— 原先只跑 ubuntu（bash 5，多字节安全），
  所以这个 bug 在 CI 里永远是绿的

### 变更

- 模板里过期的「本块由 install.sh 生成」改为实际的 `/setup-convention`
- README / CLAUDE.md 的测试数量从「12 个场景」更正为 15 个断言
- **明确最低上游版本：commit `5a5ea45`（2026-08-21）。** 更早的版本里
  `spec-driven-development` 的 Phase 0 和 `planning-and-task-breakdown` 的
  Task List Target **根本不存在**（实测 `7829ffd` / 2026-07-26：175 个文件、
  两者全树 0 命中），本插件的五个缺口全部悬空、症状是「Phase 0 永远不触发」。
  已写进 README 依赖章节、`docs/design.md` 参考章节和 `docs/upstream-analysis.md` 顶部
- `docs/upstream-analysis.md` 按 commit `5a5ea45` 重新核对：**五个缺口一个都没被上游补掉**。
  补了结果表、逐条验证命令；修正行号漂移（Task List Target 155→150、三条约束 60-64→59-63）；
  注明上游 `hooks/` 目录新增了 `sdd-cache-*` / `simplify-ignore` 但**均未注册进 `hooks.json`**

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
