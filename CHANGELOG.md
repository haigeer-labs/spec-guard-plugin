# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.5.2] - 2026-08-27

### 修复

- **P0：hook 每轮注入的「建议下一步」指向一个不存在的命令。**
  `phase-guard.sh` 三处、`setup-convention.sh` 两处、`verify-artifacts.sh` 一处
  仍写着 `/planning`，模型照着调就报 `Unknown skill: agent-skills:planning`。

  0.4.1 那次 `/planning` → `/plan` 的修复**只扫了 `*.md`**（用的
  `rglob('*.md')`），**shell 脚本一个都没碰** —— 而 `phase-guard.sh` 恰恰是
  每轮发言都注入的那个。一次不完整的替换，比不替换更隐蔽：文档全对了，
  真正到用户眼前的输出还是错的。

### 新增

- `scripts/check-command-names.py` —— 校验**用户可见输出**里提到的斜杠命令
  真实存在，已接入 `validate.sh`。检查范围刻意限定在会到达用户眼前的三处
  （`hooks/*.sh`、`templates/*.md`、`commands/*.md`）；`docs/` 与 CHANGELOG
  不查 —— 它们要能讨论「`/planning` 是错的」这件事本身。

  > 这个 lint 的第一版**漏了双引号前缀**，抓不到 `NEXT="/plan …"` 这种写法，
  > 也就抓不到它本该抓的那个 bug。加断言验证「注入坏名字要报错」之后才发现。
  > **防线本身也要被测试。**

## [0.5.1] - 2026-08-26

### 修复

- **「项目在两个 initiative 之间」被误报为断链。** 状态机原先只看
  「有 spec 且无模块 issue」就报断链,不问是不是**刻意空闲**。一个上一批全部交付、
  下一批还没起的项目 —— 7 份 spec、issue 全关、没有在做的活 —— 每轮都被催
  「去把能力图落成 issue」。又是一次假断链。

  现在区分三种情况:

  | state.json | activeModule | 判定 |
  |---|---|---|
  | 存在 | 空 | `IDLE (无活跃模块)` —— **不报断链**,这是刻意声明的空闲 |
  | 存在 | 有值但无 issue | 真断链,文案指名 `activeModule=[x]` |
  | 不存在 | — | 真断链,文案说明是缺 state.json |

  断链文案也从笼统的「没有模块 issue」改为指名道姓,便于定位。

## [0.5.0] - 2026-08-26

### 新增

- **识别归档的任务清单，不再误报。** 检查器原先分不清「归档记录」和「活清单」——
  一个已完成模块的 `todo.md` 是**历史**，把它当成「与 tracker 并存」来报违规是误报。

  约定：文件**前 10 行**内出现 `已归档` 或 `ARCHIVED`（不区分大小写）即视为归档，
  从并存检查和命名空间检查里排除。限定前 10 行是刻意的 —— 只认头部声明，
  避免正文里偶然提到就被误判。

  在一个真实项目上验证：6 份归档 + 根下两份不再报违规，**只剩唯一活的那份被正确指出**。

  这补的是设计上的一个盲区：插件**假设你从零开始**。对已经长出自己体系的项目，
  它原先只会对着历史记录挑毛病 —— 而「假断链比不报断链危害大得多」。

### 已知限制（补充）

- **插件仍假设从零开始。** 约定块是「替换」而非「适配」——如果项目 `CLAUDE.md`
  里已有冲突的目录约定，`/setup-convention` 会**追加**出两套互相矛盾的指令，
  比覆盖更糟（agent 会看到两个冲突的真源）。落地前请先人工核对现有约定。

## [0.4.1] - 2026-08-26

### 修复

- **P0：`gh issue list --parent` 这个 flag 根本不存在。** `--parent` 只在
  `gh issue create` 上；`gh issue list` 有 `parent` / `subIssues` 这两个
  **`--json` 字段**，但没有同名 flag。四处受影响：

  | 位置 | 后果 |
  |---|---|
  | `phase-guard.sh:101` | **GitHub 层从来没跑过**，每次静默落进「gh 不可用，降级判定」 |
  | `verify-artifacts.sh` | Epic ↔ 能力图交叉校验永远 skip |
  | `SKILL.md` 操作三 | `/next` 取任务命令直接 `unknown flag` |
  | `CLAUDE.md` 模板 + README | 使用者照抄照错 |

  全部改用 REST sub-issues 端点
  （`gh api "repos/{owner}/{repo}/issues/<n>/sub_issues"`，`{owner}`/`{repo}`
  占位符自动解析，仓库外干净失败）。REST 返回**所有状态**，已补 `state == "open"` 筛选。

  **12 个 phase-guard 断言全绿却没抓到** —— 它们跑在没有 GitHub 的临时仓库里，
  降级分支正是那里的预期行为，测试恰好覆盖了假象。只有真连 GitHub 才暴露得出来。

- **文档里 22 处命令名写错**：上游的拆解命令在 Claude Code 里叫 **`/plan`**，不是
  `/planning`。上游有两套等价但文件名不同的命令目录 —— `commands/planning.toml`
  与 `.claude/commands/plan.md`，**Claude Code 读的是后者**。照着旧文档敲会得到
  「命令不存在」。（skill 目录名 `planning-and-task-breakdown` 未变，那些路径引用是对的。）

### 新增

- `docs/walkthrough.md` —— 端到端实跑记录。真实仓库、真实产物、真实输出：
  `/setup-convention` → `/sync-map` → `/plan` → `/next` → `/build` →
  `/verify-artifacts`，跑完 6 个 issue 全部 `deleteIssue` 真删除、零残留。

### 变更

- 已知限制 3 从「gh 命令未经端到端实测」收窄为「仅 `/deliver` 的 PR 环节未实测」

### 已知限制（补充）

- **降级必须可观察。** 三条铁律的第 2 条「探测失败就降级，不误报」是对的，
  但一个**永远在降级**的探测器和一个坏掉的探测器没有区别。目前没有机制
  区分「这次降级是对的」和「它一直在降级」。

## [0.4.0] - 2026-08-26

### 新增

- **github 模式自适应 issue types**，个人仓库不再被挡在门外。

  0.3.0 里 `/setup-convention github` 探测到没有 issue types 就**硬阻塞**。
  实测下来这个判断过重了 —— 三个 gh 参数的可用性并不一致：

  | gh 参数 | 依赖的 GitHub 功能 | 个人免费仓库实测 |
  |---|---|---|
  | `--type Feature/Task` | issue types | ❌ `type "Task" not found; available types:`（空） |
  | `--parent` | sub-issues | ✅ 层级建立成功，REST + GraphQL 双向确认 |
  | `--add-blocked-by` | issue dependencies | ✅ 依赖建立成功 |

  **只有 issue types 是组织级的**（GitHub 员工在 community#175785 的原话：
  *available only for organizations ... not for personal repositories*）。
  而 `/next` 的第一条筛选规则「排除 `issueType != Task`」本来就冗余 ——
  模块 issue 的 sub-issue 按构造就是 task，层级已编码了这个身份。

  所以不新增 tracker 模式，改为让 `github` 模式自适应：`/setup-convention`
  探测一次，把结果写进 `.agent/state.json` 的 `issueTypes`，
  `spec-github-bridge` 据此决定加不加 `--type`。**流程一步不少**，
  只失去按 type 跨仓筛选的能力。

- `spec-github-bridge` 增加「issue types 可用性」章节和两条 Common Rationalizations

### 变更

- `/setup-convention github` 在个人仓库上从**阻塞**改为**降级 + 告知**

### 已知限制（补充）

- 硬加 `--type` 会**留下孤儿 issue** —— gh 先把 issue 建出来再校验 type，
  失败时不回滚。实测确认。所以必须读 `state.json` 的 `issueTypes`，不要试错。
- 额度（官方文档）：sub-issue 每个父 issue **100 个**、嵌套 **8 层**、
  每种依赖关系 **50 个**。本插件只用到 3 层，远未触顶。

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
