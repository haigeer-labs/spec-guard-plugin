# 并行开发上游能力审计

日期：2026-09-04
范围：addyosmani/agent-skills 当前 `main`（`020ec10a`）、obra/superpowers 当前
`main`、Codex 当前宿主边界，以及 Spec Guard v0.8.0。

## 结论

“上游限制导致自动并行开发完全不可能”不成立。

上游均允许或建议某些并行形式，但都没有提供可由 Spec Guard 直接接管的完整执行器：
从能力图调度多个写入型 worker、为每个 worker 隔离 worktree/分支、跟踪多活跃模块、
串行汇合、处理冲突/失败、回收 worker 与 worktree。当前 Spec Guard 也明确只提供候选
分析、安全门、人工 worktree 指引与 Codex 只读子代理预检。

因此，v0.8.0 不应自动触发并行写代码；这不是仅由 `Build order` 造成，而是上游契约、
宿主隔离能力和 Spec Guard 单活跃状态模型共同决定的安全边界。

## 证据

### agent-skills

- [Git workflow skill](https://raw.githubusercontent.com/addyosmani/agent-skills/main/skills/git-workflow-and-versioning/SKILL.md)
  给出 `git worktree add` 的并行开发示例。这是操作指导，不是任务调度或生命周期实现。
- [Planning skill](https://raw.githubusercontent.com/addyosmani/agent-skills/main/skills/planning-and-task-breakdown/SKILL.md)
  允许独立 slice 并行，但要求 migration、共享状态、依赖链顺序执行；没有 worker 启动逻辑。
- [Orchestration patterns](https://raw.githubusercontent.com/addyosmani/agent-skills/main/references/orchestration-patterns.md)
  唯一认可的并行编排是对独立报告的 fan-out + 主会话合并；开发生命周期则是用户驱动的顺序
  pipeline，明确反对自动 lifecycle orchestrator。
- [Build command](https://raw.githubusercontent.com/addyosmani/agent-skills/main/commands/build.toml)
  的自动路径按任务顺序执行 RED→GREEN→测试→提交，而非并行实现。

### Superpowers

- [using-git-worktrees](https://raw.githubusercontent.com/obra/superpowers/main/skills/using-git-worktrees/SKILL.md)
  为一个开发计划建立或检测一个隔离工作区；不是为多个子代理自动建立隔离工作树。
- [subagent-driven-development](https://raw.githubusercontent.com/obra/superpowers/main/skills/subagent-driven-development/SKILL.md)
  每个任务在完成、提交和审查后才进入下一个任务，并明确禁止并行派发多个 implementation
  subagent，理由是冲突。
- [dispatching-parallel-agents](https://raw.githubusercontent.com/obra/superpowers/main/skills/dispatching-parallel-agents/SKILL.md)
  支持无共享状态的并行调查/独立问题处理，但不创建 worktree/branch，也不承担合并与回收。
- [隔离失效案例 #2050](https://github.com/obra/superpowers/issues/2050) 记录了子代理未可靠绑定父
  worktree、意外提交到 `main` 的真实问题；证明“父工作树存在”不能代替子代理 cwd/分支断言。

### Codex 与 Spec Guard

- [OpenAI 官方模型指南](https://developers.openai.com/api/docs/guides/latest-model) 说明多代理是由
  宿主/应用实现的 beta 能力，提示词只能调节委派策略，不能替代隔离与生命周期编排。
- [Codex Worktrees 官方文档](https://developers.openai.com/codex/environments/git-worktrees) 区分了两种
  机制：桌面端可为多个独立聊天创建各自的 Git worktree，每个 worktree 有独立文件副本；同一
  聊天关联同一个 worktree，Codex 负责 handoff 和托管 worktree 的清理。这可隔离**多个能力图**，
  但不是插件可调用的“在一个聊天内自动派发多个写入 worker”的 API。
- Spec Guard 的
  [`parallel-subagent-preflight`](../../plugins/spec-guard/skills/spec-guard-ops/SKILL.md)
  明确规定子代理共享父工作目录，只读预检，不得创建 worktree、分支或写代码。
- Spec Guard 的能力图解析器要求 `Build order` 是包含所有模块一次的线性拓扑序；其当前
  `.agent/state.json` 工作流以单个 `activeModule` 推进。

## Build order 的准确作用

`Build order` 不是“禁止并行”的数学证明：无依赖节点可有多个合法拓扑序。
但当前格式只能表达一个线性顺序，无法标明它是展示优先级还是强制串行意图。插件不能把
“`Depends on` 为空”自动解释为写入并发授权。它是额外安全信号，不是唯一或主要技术障碍。

## 若未来实施，最低前置条件

只能作为显式 opt-in 的实验性编排器，并同时具备：

1. 向后兼容的多 worker / 多活跃模块状态及租约，不能复用单一 `activeModule`。
2. 每个 worker 独立绝对路径、分支与启动时 cwd/branch 断言；仅在 local/CLI 宿主具备可验证
   worktree 权限时启用。
3. 受控的汇合队列、冲突处理、完整测试、失败恢复和可审计清理。
4. GitHub/GitLab Issue 映射不把 `relates_to` 或 Build order 冒充运行时依赖。
5. Codex Desktop 无法提供这些隔离保证时稳定降级到当前的只读预检与人工指引。

在这些条件未实现和真实验证前，维持 v0.8.0 的保守行为是正确选择。

## Codex Desktop 的独立任务结论

若用户在 Codex Desktop 为同一 Git 项目手动新建两个 **Worktree** 聊天，则两个聊天的
`spec/`、`tasks/`、`.agent/state.json` 分别位于各自 checkout，不会发生本地状态文件覆盖。
这使“能力图 A”和“能力图 B”作为两个独立 initiative 并行推进成为可行工作流。

仍需保持三个边界：两个能力图不能修改相同代码区域或同一远端 Issue；每个工作树应从明确
的基线创建并在完成后由用户合并/PR；插件只在各自聊天中运行，不能自动创建、命名或回收
Desktop 聊天。若两个聊天都选择 Local 或同一个 permanent worktree，它们会共享文件系统，
现有单 `state.json` 模型仍会冲突。

## Worktree 隔离与远端 tracker 的边界

Codex Desktop 的托管 worktree 是实际 Git worktree：它在 `$CODEX_HOME/worktrees` 建立独立
checkout，默认 detached HEAD；每个 checkout 有自己的工作文件和 index，但共享同一 Git
common metadata。创建分支后，同一分支不能同时被两个 worktree checkout。这隔离本地
`state.json`，不隔离 GitHub/GitLab、远端分支命名或 PR/MR 合并。

因此两个**不同 initiative**可以各自在独立 worktree 同时创建各自的 Epic/Issue：单次
GitHub/GitLab Issue 创建是独立远端操作，不会覆盖另一个 worktree 的本地 state。但是现有
`sync-map` 的续跑/去重键只在当前 `.agent/state.json`：它不会跨 worktree 用远端 marker
查找“同一个 initiative 已由另一个聊天投影”。若两边实际是同一能力图或对同一 initiative
同时执行同步，就可能创建重复 Epic、模块 Issue 或 task Issue；若两边修改同一远端 Issue，
也没有分布式锁或乐观并发控制。

推荐的现阶段规则：一个 Desktop Worktree 聊天只拥有一个 initiative；其 state、能力图、
远端 Epic 与分支都带唯一 initiative 标识；不同 initiative 才允许并行；涉及同一代码边界、
同一 Issue 或同一目标分支的交付仍须串行协调。未来若要自动编排多个 Desktop 聊天，必须先
增加远端 initiative identity、跨 worktree lease/锁、分支命名与 PR/MR 汇合策略，不能仅靠
本地 state 隔离。

## `/next` 的范围与并发风险

GitHub `/next` 不会在整个仓库执行“找下一个开放 Issue”：它先从当前 worktree 的
`.agent/state.json` 读取 `activeModule`，取得 `modules.<activeModule>.issue`，随后只查询该
module Issue 的 `sub_issues`。它再排除已关闭、被阻塞、已在**当前分支**完成及被他人认领的
task。GitLab `/next` 同样先由本地 state 得到 module Issue，只在该 module 的 `plan.md` 远端
Issue 索引中选择仍为 `opened` 的 task。

故两个 worktree 各自拥有不同 initiative / module Issue 时，`/next` 不会领取对方的 task。
但两个 worktree 若复制了相同 state、指向同一个 module Issue，则当前设计没有跨 worktree
原子领取：GitHub 的“查看未认领 → 选择 → add-assignee”存在竞态，且同一账号下 assignee
不是互斥 lease；GitLab 的选择流程也没有 claim/lease。两个聊天可能同时开始同一 task，或
一方关闭模块后另一方在远端校验时停止。此模式当前不受支持，必须串行，直到引入远端 worker
identity 与原子租约协议。

## Worktree 默认化与插件自管的评估

### Codex Desktop 的可控边界

Codex 官方文档描述的路径是：在**新聊天**编辑器下选择 Worktree、选择起始分支，再发送任务；
由 Desktop 创建 managed worktree。官方文档没有公开“由插件把所有新聊天强制设为
Worktree”的设置或插件 API。插件在聊天已经启动后才加载，因果顺序上不能把当前聊天从 Local
变成 managed worktree，也不能替 Desktop 创建、关联或回收一个可见聊天。

因此不能把“用户未选择 Worktree”静默修复成 Desktop managed worktree；也不能承诺在
Claude Code、CLI 或其他宿主获得同样的 Desktop 生命周期。可以做的可靠体验是：用户明确启用
隔离策略后，插件在第一个会写入的命令前检测当前 checkout；若是 Local，则拒绝启动并给出
“以 Worktree 新建此任务”的明确指引。此为 fail-closed 检测，不是强制创建。

### 插件自行 `git worktree add` 的边界

agent-skills 的 Git workflow skill 仅给出 `git worktree add` 的手工命令；其 orchestration
patterns 明确把开发生命周期保留为用户驱动的顺序 pipeline，并没有 host-agent 启动、cwd 绑定、
合并或清理协议。Spec Guard 当前同样没有调用 Desktop 创建任务的能力。

插件即使创建额外目录，也无法把**正在运行的宿主 agent**迁移到新目录，亦无法可靠地在该目录
启动一个写入型子任务并使其成为 Desktop 所管理的聊天。这样做只会留下未受宿主管理的 worktree
和分支，反而比“用户先选择 Worktree”更难回收。因此 v0.8.0 不应新增“插件自动创建 worktree”
这一表面能力。

### 可实施的最小策略（建议作为未来独立功能）

1. 引入显式 `isolationPolicy`（默认 `manual`，可选 `worktree-required`）；不能默认为所有项目
   开启，以免破坏 Local、Claude Code 和不需要并行的既有工作流。
2. `worktree-required` 仅在任务初始化/`sync-map` 前做检测：当前仓库根目录的 `.git` 是 worktree
   链接文件、当前路径在 `git worktree list --porcelain` 中，且当前分支/HEAD、基线 SHA 可读。任一
   条不满足时停止写入并降级为 UI/CLI 指引。检测只证明隔离 checkout 存在，不能证明任务安全。
3. 用规范化 remote、基线 SHA 与 capability-map digest 生成 initiative identity；先查**共享的、可
   原子声明**的 lease，成功后才允许同步或 `/next`。本地 Desktop 的多个 worktree 可在 common
   Git dir 下以原子目录创建短租约；同一项目的另一个 clone、GitHub 与 GitLab 则必须使用真正的
   远端 compare-and-set/锁服务，不能把 Issue assignee、评论或 label 假装成锁。
4. 检测到相同 identity 的活跃 lease 时，显示拥有者、worktree/任务标识与过期时间，并只允许
   “只读查看、等待、显式接管已过期 lease”；禁止 `/sync-map`、`/next`、`/deliver` 的写操作。
5. 不同 identity 仍须通过已有 safety gate 检查路径、公共 API、迁移、环境资源和目标分支。identity
   不同只表示“不是同一 initiative”，不代表代码无冲突。

这套策略能解决“两个不同聊天意外跑同一能力图”的本机事故，但跨 clone 的可靠排重需要独立的
远端协调能力；在没有该能力前，应将跨 clone 检测明确标为 advisory，不能承诺互斥。

## 四个宿主的 Workspace / Worktree 兼容性（2026-09-04）

这里的“Workspace”统一指运行 agent 的仓库工作目录；“隔离”仅指标准 Git linked
worktree。四个宿主都能在一个已有 Git worktree 中运行插件，但它们**创建、切换和回收**
worktree 的宿主能力并不一致。

| 宿主 | 原生启动隔离方式 | 默认/自动行为 | 插件可依赖的事实 |
| --- | --- | --- | --- |
| Codex CLI | 无 `--worktree` 参数；先用 Git 创建，再以 `codex -C <path>` 启动 | 不自动创建 | 当前 cwd 是一个 Git checkout |
| Codex Desktop | 新聊天选择 Worktree 和基线分支；Desktop 创建 managed worktree | 用户选择环境；每个 managed worktree 通常绑定一个聊天 | 当前 checkout，不依赖 Desktop 路径、任务 ID 或清理策略 |
| Claude Code CLI | `claude --worktree [name]` / `-w` | 仅传 flag 时创建 | 当前 cwd 是一个 Git checkout |
| Claude Code Desktop（Code tab） | 多个本地并行 session 自动使用 worktree；可配置位置与分支前缀 | 并行 session 自动隔离；Local session 仍可直接操作原目录 | 当前 checkout，不依赖 `.claude/worktrees` 的固定位置 |

Codex 本机 CLI help（2026-09-04）只公开 `-C/--cd` 与 `--add-dir`，没有
`--worktree`。这不是证明未来永远不存在该参数，而是当前版本不应将它写入插件承诺。
Claude CLI 明确公开 `--worktree`，Claude Code 工具参考还列出可在主 session 中创建并切换
worktree 的 `EnterWorktree`；该工具不适用于 subagent。Codex Desktop 的 managed worktree
使用 detached HEAD、位于 `$CODEX_HOME/worktrees`，其复制 ignored 文件和自动清理规则只适用
Desktop 托管工作树；Claude Desktop 默认在 `<project-root>/.claude/worktrees/` 管理并行 session。

### 跨宿主统一策略

插件不应试图统一“谁创建 worktree”，而应统一**运行时契约**：

1. 仅以标准 Git 事实识别环境：仓库根、`git worktree list --porcelain`、当前 HEAD/branch、
   common Git dir 与干净度；不得根据 `$CODEX_HOME`、`.claude/worktrees` 或窗口标题判断。
2. 保持现有默认 `manual`。开启 `worktree-required` 后，在写操作之前 fail-closed：当前路径不
   是 linked worktree 则停止，并按检测到的宿主输出启动指引；未知宿主输出通用 Git 指引。
3. 将“进入隔离环境”放到**启动器**而不是插件内部：Codex Desktop 使用 UI 的 Worktree；Claude
   Desktop 新建并行 session；Claude CLI 使用 `claude -w <name>`；Codex CLI 由一个可选 shell
   wrapper 先 `git worktree add` 再 `codex -C <path>`。该 wrapper 启动的是新 agent，不能也不应
   试图迁移当前 agent。
4. 所有宿主使用同一 initiative identity、lease 和 `/next` 保护协议；宿主特有的会话标题、
   归档、自动清理只是增强体验，不能作为正确性的前提。

因此“同一插件在四处正常运行”是可实现的，但含义是同一 Git workspace 契约、相同的安全降级
与同一 tracker 协议；不是四个宿主提供相同 UI 或由插件获得相同的原生任务调度 API。

## 修正后的 Desktop 适配结论

不应把“统一”实现成所有宿主都由插件裸调用 `git worktree add`。这只能统一目录，丢失
Desktop 对会话、标题、恢复、归档和自动清理的所有关联。正确边界是：**Spec Guard 拥有控制面，
宿主适配器拥有 worker 的目录和会话生命周期。**控制面统一生成 initiative identity、module
lease、基线 SHA、worker prompt、状态变更、测试证据与汇合决定。

- **Codex CLI**：适配器可完全自动化：控制器建 worker worktree/branch 后，以
  `codex -C <path>` 或 `codex exec -C <path>` 启动 worker。当前 `codex-cli 0.150.1` 的 help
  没有 `--worktree`，因此此适配器自己管理目录是正确的。
- **Codex Desktop**：当当前任务暴露原生的“创建 project worktree task”能力时，适配器应让
  Desktop 按指定起始分支创建一个 Worktree task，并写入可见标题
  `SG 自动｜<initiative>｜<module>｜执行中`。控制器保存 task id 与 lease；完成后更新标题为
  `可汇合`/`可回收`，再在用户确认后交付和归档。原生 `spawn_agent` 不可替代它，因为其子代理
  共享父目录。若原生创建任务能力不存在，停止自动并行，不用脚本伪造不可见 Desktop worker。
- **Claude Code Desktop**：官方承诺并行 Code session 自动使用 Git worktree，且当前 session
  的任务面板可以显示 subagent。Claude 的 `EnterWorktree` 可把主 session 切换到新建或已有
  worktree（不能为 subagent 使用）；另外其 `Agent` 子代理隔离能力须由运行时 feature detection
  和用户确认后才可作为 worker 后端。若 `Agent` worktree isolation 可用，控制器给每个 worker
  一个确定的名称、module lease 和 prompt；若不可用，则使用 Desktop 的新并行 session，并由插件
  在 session 启动后登记其实际 worktree。Desktop 没有公开的插件 API 来静默创建任意数量的
  sidebar session，因此不能把“脚本模拟点击 UI”当成稳定方案。

这使 CLI 是全自动后端；Codex Desktop 和 Claude Desktop 是“原生 worker 后端、统一控制面”。
它们对用户的执行语义一致（同一 lease、相同保护和回收状态），但不承诺相同的窗口行为。
正式实施前必须在两种 Desktop 的真实项目中验证：worker 的 cwd/branch、跨 worker state、
tracker claim 竞态、故障恢复、归档后 worktree 回收，以及宿主不支持时 fail-closed 降级。
