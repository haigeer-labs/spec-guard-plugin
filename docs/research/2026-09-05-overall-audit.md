> 归档说明：本文件保存 2026-09-05 原始审计结论，不代表整改已完成。当前整改范围见 [整改与收尾评审稿](2026-09-05-audit-remediation-scope.md)。原报告中的临时日志路径仅适用于原审计环境；正式关闭问题时必须附新的持久化证据。

# Spec Guard 整体审计：定位、架构、四端覆盖与并行可用性

日期：2026-09-05。对象：`/Users/vilin/Documents/gs/spec-guard-plugin`。

## 1. 结论先行

**方向合理，但功能成熟度不均衡；目前不能把“多 Agent 并行开发、汇合、回收”作为已完成的可靠功能对外承诺。**

你的目标不是再做一个大全型开发助手，而是补齐 agent-skills 从开发方法到项目持续迭代之间的落地缺口：让人和 AI 清楚地知道项目有哪些能力、当前做什么、任务在哪里、哪里断链、过去如何演进，并以较少的协调成本稳健交付。

推荐的一句话定位：**Spec Guard 是 agent-skills 的项目工作流一致性与能力演进追踪插件。**

目前最有价值的部分是多模块产物命名空间、tracker 映射、阶段事实检测和历史证据保存。主要欠账是 GitLab 语义一致性、历史摘要准确性，以及最新并行执行链路。不是所有欠账都需要“再加一个功能”；不少应通过修正契约、减少重复实现和补真实验收来解决。

必须更正之前的完成判断：模块关闭、PR 合并和测试全绿，不足以说明并行需求已实现。此次实际复现出了会阻断正常流程或误判安全状态的问题。

## 2. 审计基线和证据边界

| 对象 | 本次核验结果 |
| --- | --- |
| 当前 main | `c2f247ce5b76fe87887206b0761ef8d16a17ea98` |
| 最近发布 | `v0.8.0`，2026-09-04 发布；tag 指向 `8ae87e62782172bae17d9d74c25c65d3d9d149e0` |
| main 相对发布包 | 插件目录多出/改变 20 个文件、增加 2075 行，主要是并行执行与登记 |
| 版本标识 | main 与已安装包仍都标为 `0.8.0`，但内容不同 |
| 本地 Codex 安装 | `~/.codex/plugins/cache/spec-guard-marketplace/spec-guard/0.8.0`，不含最新 execute/integrate/reclaim/register-worker/status 命令和执行库 |
| 上游核对 | agent-skills 已安装 0.6.9，并核对上游提交 `84ee50673804b95c287d1e4eb4f1c1dad7c5188a` 的 spec/planning 契约 |
| 本地宿主 | Codex CLI 0.150.1；Claude Code 2.1.259；测试环境 macOS |

发布信息：[GitHub v0.8.0](https://github.com/yizhongkaimail-collab/spec-guard-plugin/releases/tag/v0.8.0)。main 有未发布实现本身正常；问题是不能据此声称用户已安装的同名版本具备这些功能。

本次完成源码交叉审阅、隔离 Git fixture、离线 tracker 桩测试、真实 Codex 启动检查和既有回归测试。没有向 GitHub/GitLab 测试项目写入 Issue/PR/MR，没有宣称本次重新完成了四端真实开发 E2E。历史 walkthrough 可以作为历史证据，但不能自动覆盖最新 main 的行为。

## 3. 架构：它实际上由哪些层构成

| 层 | 主要实现 | 职责及可信度边界 |
| --- | --- | --- |
| 宿主入口 | Claude `commands/*.md`、Codex `spec-guard-ops`、Claude Chat MCPB | 入口形态不同，不等于功能自动对等 |
| 工作流约定 | templates、GitHub/GitLab bridge skills | 指导模型选择路径、任务和交付；不少规则是提示词，不是强制执行代码 |
| 确定性检查 | phase-guard、verify-artifacts、spec-digest、capability_map | 探测阶段、校验产物、识别映射变化；不等于证明业务实现正确 |
| 当前与历史状态 | `.agent/state.json`、能力图、模块 spec/plan、history ledger/checkpoints | 当前上下文与归档证据；历史摘要的业务含义目前存在缺陷 |
| tracker 适配 | `gh`/GitHub bridge、`glab`/GitLab bridge 与同步脚本 | 远端任务事实源；两个 tracker 的恢复与选任务语义尚不等价 |
| 并行执行实验层 | common-dir 下的 run/lease/worker/process，worktree 和 CLI adapters | 已有目录隔离、部分互斥和身份验证；尚未形成可靠执行闭环 |

值得保留的架构选择：不复制上游全部开发技能；命名空间明确；阶段 hook 只报告事实；GitHub/GitLab 显式分流；history 用校验和保存证据；区分插件所有与宿主所有的 worktree，避免误删宿主资源。

主要结构问题：同一逻辑分别出现在 Markdown 指令、Python、Shell、JavaScript 中，容易漂移。所谓“唯一能力图解析器”尚未真正覆盖 GitLab 同步与 MCP 预览；同样，Claude `/next` 中的 worker 保护没有一致落入 Codex ops 路由。应优先统一关键判据和数据协议，而非再复制一套入口逻辑。

## 4. 四端功能覆盖矩阵

下表评估当前 main 的实现/入口，不是四端全部通过真实 E2E 的证明。已安装 v0.8.0 还不含最新执行层。

符号：**有**＝存在相应实现/入口；**部分**＝有限入口、行为缺陷或条件限制；**未闭环**＝不足以兑现完整能力；**待验**＝宿主文档支持，但插件真实链路未验证。

| 功能 | Codex CLI | Codex 桌面 | Claude Code CLI | Claude 桌面的 Code 模式 |
| --- | --- | --- | --- | --- |
| 模块目录约定、setup | 有，skill 路由 | 有，skill 路由 | 有，slash/skill | 宿主支持插件，待验 |
| phase、产物/指纹校验 | 有，脚本/hook | 有，脚本/hook | 有，脚本/hook | 可复用插件机制，待验 |
| GitHub 能力图→Issue、next/deliver | 有，依赖 gh/认证/模型遵循 | 同左 | 有 | 同类机制，待验 |
| GitLab 能力图→Issue、next/deliver | 部分，有下面列出的缺陷 | 部分 | 部分 | 还需真实验证 |
| 历史迁移、校验、暂停/恢复/完成 | 有，但历史语义有缺陷 | 同左 | 同左 | 入口与流程待验 |
| 并行候选/边界/人工指引 | 有，但边界判定有漏洞 | 同左 | 同左 | 可复用，待验 |
| 原生子 Agent 只读预检 | 有条件，必须存在 spawn_agent | 同左 | 无对应 Codex 专用入口 | 无对应入口 |
| 插件创建 controller worktree | 底层库有；ops 入口不完整 | 不会自动把桌面任务迁入该目录 | execute 命令可创建目录 | 不等于创建/切换 Code 任务 |
| 插件启动真实开发 worker | 未闭环；真实 Codex 启动失败 | 未实现桌面任务自动执行闭环 | 未闭环；只测过假 CLI | 未实现桌面任务自动执行闭环 |
| 登记已有桌面 worktree | 可调用登记器协助，但不是 CLI 自身宿主能力 | 仅 register-only，身份取得及 E2E 待验 | 可调用登记器协助 | 仅 register-only，E2E 待验 |
| worker 的 next/deliver 安全绑定 | ops 路由缺保护 | host-owned 路由缺保护 | 只保护特定插件分支前缀 | native 分支不在该保护范围 |
| 汇合、完成验证、资源回收 | 未闭环 | 未闭环；宿主资源不由插件回收 | 未闭环，有确定缺陷 | 未闭环；宿主资源不由插件回收 |

**必须纠正产品名称混淆：Claude Desktop 的 Chat 模式与其中的 Claude Code/Code 模式不是同一个接入面。** 当前仓库 MCPB 只读能力适用于 Chat 扩展，不能据此断言桌面 Code 模式也只能读。官方说明 Code 模式可用插件；当前文档的“四端矩阵”把这两者混在一起。[Claude Code 桌面官方文档](https://code.claude.com/docs/en/desktop)

Claude Chat MCPB 当前只暴露 phase、verify、verify_history、sync_map_preview；write_operation 只返回说明，不执行写入。这一只读定位本身合理，但应作为额外接入面，而非代替 Claude Code 桌面端的兼容性验证。

四端一致应指“同样的输入含义、安全边界、任务身份、结果格式和可解释降级”，不必强求菜单、slash 命令、进程启动方式完全一样。当前依赖 Bash/Git/Python，不能把本次 macOS 结果推广为 Windows 原生、WSL、远程和云环境均可用。

## 5. 问题清单（按风险排序）

P1：应在推荐相应功能稳定使用前修复；P2：需要修复的可靠性/一致性问题。这里没有把所有问题都渲染为安全漏洞，也没有仅凭猜测报告 P0。

### F01 / P1：真实 CLI worker 不能按当前适配器执行开发

适配器仅启动 `codex -C <worktree>` 或 `claude`，同步捕获 stdout/stderr；没有任务提示，没有非交互执行协议，也没有 PTY。真实 Codex 在相同非终端条件下退出 1，报 `Error: stdin is not a terminal`；调整 TERM、在获准的沙箱外复核，仍是该结果。

即便程序退出 0，代码也直接标记 completed，没有验证模块产物、测试或交付。测试用假 codex/claude 输出 cwd/argv 后退出，因此测到的是参数传递，不是真实任务执行。Claude 的实际模型开发本次未运行，不将 Codex 的实测错误冒充为 Claude 的实测错误。

证据：[适配器](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/hooks/parallel_cli_adapters.py:18)、[假 CLI 测试](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/hooks/test-parallel-cli-execution.sh:16)。

建议：先明确“进程退出”和“任务验收通过”是不同状态；再选择有正式任务输入/结果输出的宿主执行接口。仅更换一个启动参数不足以完成整个修复。

### F02 / P1：汇合命令中的 JSON 输入通道错误

`printf STATUS | python3 - ... <<'PY'` 同时把 stdin 用作 Python 脚本和 JSON 数据，脚本中的 json.load(sys.stdin) 实际读不到 JSON。直接提取真实命令的 Bash 代码块执行，得到 JSONDecodeError；reclaim 的模块解析也有相同写法。

证据：[parallel-integrate](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/commands/parallel-integrate.md:25)、[parallel-reclaim](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/commands/parallel-reclaim.md)。

建议：统一到可执行脚本入口，测试真实命令，而不是只断言文档含有几个关键词。

### F03 / P1：两个模块汇合的正常场景被基线规则阻断

integrate 要求 controller 当前 HEAD 等于 run 初始 base。合并第一个有提交的 worker 后 HEAD 必然变化，第二个同 run 的独立 worker 即使无冲突也被拒绝。文案要求人工更新/重建上下文，所以这不是无需干预的多模块汇合闭环。代码还把当前 checkout HEAD 称为“默认分支 HEAD”，却没有在此核对当前分支身份。

证据：[基线条件](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/commands/parallel-integrate.md:52)。这是源码推导，不能与已运行的 F02 混称为完整汇合实测。

建议：区分初始 base 与 controller 汇合进度；每次汇合按明确的集成分支和结果重新验证，而非直接删除安全条件。

### F04 / P1：桌面 worker 唯一性检查存在竞态和跨 run 缺口

登记器先扫描现有 worker，再分别领取模块 lease。两个不同模块同时通过扫描，就能把同一 host ID/同一 worktree 登记两次。用 barrier 控制交错顺序，两个调用均成功；这是可复现的 TOCTOU 竞态，不依赖碰运气。不同 run 的扫描会跳过已有记录，同一目录也可连续登记两次。

证据：[登记器](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/hooks/parallel-desktop-register.py:43)。

建议：在同一 Git common-dir 内对活动 worktree/宿主 worker 的占用做原子约束；任务去重必须包含 initiative/tracker 身份，不能仅凭 module 名。也要设计终态释放和异常恢复。

### F05 / P1：路径拼写可使安全门漏报实际重叠

模块 A 声明 `src/`，模块 B 声明 `src/file.py`，实际目录包含关系明确，但报告返回 manual-parallel-eligible。输入未归一化，字符串比较把尾斜杠变成双斜杠匹配。

证据：[路径判断](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/hooks/parallel_safety_gate.py:28)。

建议：规定并校验规范化路径，再处理大小写、符号链接等平台边界；“声明无冲突”仍不是实际 diff 合规或运行资源隔离的证明。

### F06 / P1：GitLab sync-map 重跑会创建重复 Issue 并替换映射

同步脚本不根据现有 state/远端标记复用 initiative 和 module Issue，确认执行后直接 POST。对同一个两模块项目运行两次，记录到 6 次创建，而非保留原来的 3 条。中途失败后重跑也有相同风险。

证据：[同步创建](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/hooks/sync-map-gitlab.sh:51)。本次是执行真实脚本、由离线 glab 桩记录请求，没有在用户 GitLab 上制造垃圾 Issue。

建议：同步必须可恢复、可重试且不重复创建；恢复映射优先于覆盖。当前脚本还未写 goalDigest，应统一与检查器的投影契约。

### F07 / P1：worktree 隔离尚未闭合到 next/deliver 的任务选择

Claude 命令仅在分支名为 `spec-guard/<worker-id>` 时进入 worker 保护。host-owned native 分支不满足该前缀；Codex ops 的 next/deliver 又直接路由到 bridge，没有同等保护。bridge 仍从当前 state 的 activeModule 取任务。复制出的 state 不会自动知道新窗口负责哪个模块。

证据：[Claude next](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/commands/next.md:5)、[Codex next/deliver](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/skills/spec-guard-ops/SKILL.md:210)。这是明确的路由缺口；本次没有让两个真实 Agent 抢用户的 Issue 来证明危害。

建议：所有入口共用“当前工作区→明确的 initiative/module/task”解析和校验，不能以分支前缀代替身份。失败应报告上下文未知，不得全仓库找一个“下一个”。

### F08 / P2：GitLab next 缺少 GitHub 已有的本地完成排除

GitLab next 仅从 plan 索引选 opened task。模块 MR 尚未合并时，已经在本地完成的 task 仍可能 opened，因而再次被选中。相应规则也没有 GitHub 的 assignee 过滤；即便按账号分配，同一账号的两个 AI 会话仍需要更细的任务占用机制。

证据：[GitLab next](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/skills/spec-gitlab-bridge/SKILL.md:95)、[GitHub 对照规则](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/skills/spec-github-bridge/SKILL.md:327)。本项为源码契约缺口，未在真实 GitLab 远端复测。

### F09 / P2：回收后 lease 仍显示 claimed；宿主所有权又被显示成可回收状态

真实 fixture 中回收成功删除 worktree/branch/worker manifest 后，lease_status 仍返回 claimed。另一方面，host-owned worker 一登记就显示“宿主可回收”，没有检查任务是否结束或成果是否安全保存。资源“归谁管理”不等于“现在可以删除”。

证据：[reclaim](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/hooks/parallel_worktree_lib.py:134)、[host 状态文案](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/commands/parallel-status.md:9)。

建议：保留完整终态证据，并区分 registered/running/result-ready/integrated/reclaimable/reclaimed/unknown；无法观察宿主时显示“由宿主管理，完成状态未核验”。不应自动清除不明 lease。

### F10 / P2：登记器接受文件名与内容 runId 不一致的 run

把 f…f.json 内 runId 改为 9…9，登记成功；worker ID 按 9…9 派生，返回 manifest 的 runId 却仍是 f…f。这会破坏账本相互引用和审计归属。

证据：[run 加载和 manifest 生成](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/hooks/parallel-desktop-register.py:75)。本项有隔离复现。

### F11 / P1：能力历史的摘要不是实际历史语义

归档代码把 responsibility 写成 module ID，dependsOn 一律清空，status 只按 activeModule 推断为 in-progress 或 not-started，时间写为字符串 now。当前真实 history 中 initiative 94 的最后事件是 completed，但五个模块都记为 not-started。

这不表示五个模块真的从未开发，也不表示归档文件丢失；它说明结构化历史摘要不能作为项目完成情况的可靠事实。文件 hash 正确只能证明快照未变，不能证明摘要内容正确。

证据：[事件构造](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/hooks/initiative-lifecycle.sh:139)、[当前历史账本](/Users/vilin/Documents/gs/spec-guard-plugin/spec/CAPABILITY-HISTORY.json)。

建议：职责/依赖来自对应版本的能力图，完成状态来自可追溯的交付证据；无法确定用 unknown，不要制造 not-started 或 completed。

### F12 / P2：拒绝上游合法的并列 Build order

上游例子是 `identity → billing, notifications → reporting`，当前 parser 只按箭头分割，把 `billing, notifications` 当成一个模块，随后拒绝。使用上游原样表格和顺序调用真实解析器已复现。

证据：[本地解析器](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/hooks/capability_map.py:80)、[上游固定提交](https://github.com/addyosmani/agent-skills/blob/84ee50673804b95c287d1e4eb4f1c1dad7c5188a/skills/spec-driven-development/SKILL.md)。

这直接反驳了“上游 Build order 决定绝不可能并行”的笼统说法。但上游表达并列依赖也不等于它已经提供锁、宿主调度、结果集成等运行机制。

### F13 / P2：测试与发布证据不足以支撑当前承诺

并行 workflow integration 测试检查 Markdown 中有没有字符串，甚至明确断言 execute 中不得启动 CLI；未运行汇合代码块。validate/CI 主链没有接入新增的并行套件。此次 `gh run list --limit 5` 返回空数组，未取得可核对的近期云端 CI 运行证据；仓库自身也记录过 Actions 长期未运行。

证据：[workflow 测试](/Users/vilin/Documents/gs/spec-guard-plugin/plugins/spec-guard/hooks/test-parallel-workflow-integration.sh:7)、[validate](/Users/vilin/Documents/gs/spec-guard-plugin/scripts/validate.sh)、[CI 定义](/Users/vilin/Documents/gs/spec-guard-plugin/.github/workflows/validate.yml)。

现有测试不是没有价值；问题是测量目标偏向“结构存在、坏输入拒绝、桩调用正确”，缺少“用户完成这件事”的验收。近期新增代码未发布、安装内容不一致，也让源代码测试与用户体验脱节。

## 6. 并行需求到底可不可行

### 两个独立需求、两个桌面任务

可行，不受“单个 activeModule 字段”从原理上禁止。一个真实 worktree 对应一份工作区文件，两个不同 worktree 的 state 可以各有一个 activeModule。必须在初始化时分别绑定需求/能力图/任务，不能沿用同一初始 state 后让两个窗口自由执行 next。

需要额外协调的是共同的 Git refs/common-dir、远端 tracker、能力历史汇总、相同文件与数据库/端口等运行资源。不同聊天题目不证明它们没有这些交叉。

### 同一个能力图内的两个模块

依赖关系可帮助筛选候选，但还需要文件/接口/迁移/配置/测试资源检查、模块级任务绑定、领取互斥、结果验收和汇合顺序。当前实现有这些概念的一部分，尚不足以稳定执行。

### 是否应该把 activeModule 改为数组

**不应先改成数组。** 保留每个 worker 工作区一个明确 activeModule 通常更简单；controller 的共享执行账本记录多个 worker。需要先决定 canonical 状态由谁更新、worker 如何只读/投影、历史何时合并。直接把字段改为数组会破坏上游和现有 next/deliver 的单模块语义，却没有解决抢任务。

### 原生能力边界

Codex 桌面的 Worktree 模式确实基于 Git worktree，默认可能是 detached HEAD，可通过 Create branch here 建分支。当前登记器拒绝 detached，因此要提供明确接入步骤，不能将该拒绝推导为宿主不支持。[Codex 官方 worktree 文档](https://learn.chatgpt.com/docs/environments/git-worktrees)

Claude Code 支持 CLI worktree 和桌面自动 worktree；这些是目录隔离能力，不是 Spec Guard 的 tracker/历史协调实现。[Claude Code 官方 worktree 文档](https://code.claude.com/docs/en/worktrees)

当前插件的 Codex spawn_agent 入口只允许只读预检，而且明确共享父工作目录。桌面入口只有 register-only。两者都不能描述成“能力图通过后自动创建两个隔离开发 Agent”。

## 7. 功能边界：哪些应保留，哪些应克制

| 功能方向 | 建议 | 原因 |
| --- | --- | --- |
| 多模块 spec/plan 命名空间 | 核心保留 | 直接补上游多模块落地时的路径冲突 |
| tracker 绑定、幂等同步、任务选择 | 核心保留 | 连通规范与实际开发事实，不另造任务系统 |
| 阶段检测、漂移检测、恢复指引 | 核心保留 | 降低上下文丢失和流程断链成本 |
| 能力历史、版本差异、证据追溯 | 核心加强 | 与你的长期项目认知目标最贴合 |
| 并行可行性判断、任务身份、防重复领取 | 合理延伸 | 保护上述工作流在多会话下仍一致 |
| worktree 创建/验证的薄适配层 | 可保留为可选能力 | 服务于隔离，但不能变成硬绑某客户端 |
| Agent 进程调度、桌面任务创建/隐藏/回收 | 建议独立实验适配层 | 宿主差异大、权限复杂、维护成本高，不能侵入核心链路 |
| 重新实现通用 TDD/代码审查/规划方法 | 不建议 | 重复上游能力，扩大契约冲突面 |
| 全量项目管理、通用多 Agent 平台 | 不建议纳入核心 | 偏离细分定位，引入另一个任务事实源和庞大状态机 |

上游 planning 已允许外部 tracker 并要求避免双写任务列表，因此桥接方向合理；但应把“上游原生规则”“本插件新增约束”“宿主能力条件”分别写清楚，而不是把插件自己的限制称为上游不可改变的限制。[上游 planning 契约](https://github.com/addyosmani/agent-skills/blob/84ee50673804b95c287d1e4eb4f1c1dad7c5188a/skills/planning-and-task-breakdown/SKILL.md)

## 8. 用户痛点与后续优先级

| 开发痛点 | 当前帮助 | 仍需补齐 |
| --- | --- | --- |
| 多模块产物覆盖、找不到计划 | 命名空间和映射已有实际价值 | 所有入口统一选择上下文 |
| AI 忘记做到哪里、重复工作 | phase、next、tracker 提供帮助 | GitLab 本地完成排除、跨会话任务占用 |
| 规范、代码、Issue 越走越远 | 指纹和产物检查能识别部分漂移 | 明确指纹不证明实现符合 spec；连接验收证据 |
| 想知道项目已有能力及演进原因 | 归档快照可回看 | 准确的历史摘要、跨 initiative 能力索引/差异 |
| 独立任务想并行却怕串单 | readiness、安全门、worktree 是起点 | 上述执行/领取/汇合问题尚未解决 |
| 操作多、频繁询问、看不懂状态 | 命令覆盖较全 | 按用户意图给一条下一步；权限与业务确认分开 |

建议先修复现有闭环，再决定新功能。优先顺序：

1. **纠正可信度**：文档标出 stable/experimental/unverified，显示安装版本与内容摘要；不要立即把当前并行代码打成稳定版。
2. **修正确性**：优先处理 F01–F07、F11；为其添加真实入口级回归，再处理恢复、状态及上游格式兼容。
3. **收紧任务上下文**：worktree 与 initiative/module/task 显式绑定；所有 next/deliver 共用入口；跨会话重复领取可检测、可解释。
4. **建立真实验收门禁**：真实两个 worker 在不同文件开发→分别测试→汇合两份成果→核对 tracker 与历史→回收；故障和重启也必须测。
5. **改善核心体验**：一个只读健康检查给出当前能力图、活跃任务、漂移、安装差异和下一步；能力历史支持查询/对比，而不是再堆命令。

值得后续考虑的有限延伸：可追溯的 capability catalog、从历史到当前能力的派生视图、恢复/交接包、实际 diff 对声明边界的检查。它们都应复用现有事实源，不再维护一份必须手工同步的“项目真相”。

## 9. 测试证据与下一轮验收

本轮在独立本地 clone 中运行 validate 和所有 18 个 hooks/test-*.sh，全部退出 0；phase 为 129 条通过、verify-artifacts 为 72 条通过。详细结果见同目录日志。另行运行了上述缺陷复现，故“回归通过”和“发现实际缺陷”并不矛盾。

复现脚本：[reproduce.py](/private/tmp/spec-guard-audit.kIuFi1/reproduce.py)。结果：[reproduction-results.txt](/private/tmp/spec-guard-audit.kIuFi1/reproduction-results.txt)。基线：[validate.log](/private/tmp/spec-guard-audit.kIuFi1/validate.log)。

下一轮修复验收至少覆盖：

- GitHub/GitLab：新项目首次同步、老项目升级、重复同步、创建中断恢复、未合并前 next、交付与归档。
- 两个独立 initiative，以及同图独立模块：同模块争抢、同目录双登记、不同 run 重复登记、不同账号/同账号多会话。
- 真实宿主：四端各验证插件加载与目标 cwd；执行模式各自验证任务输入、失败传播、结果产物，不使用假 CLI 代替。
- 汇合：第一个模块合入后第二个仍能安全验证；默认分支推进、有冲突、只读/脏工作区、未完成退出、回收失败重试。
- 历史：状态、依赖、责任、时间、Issue/PR/MR 链接与归档快照一致；旧 schema/部分数据缺失应显式 unknown。
- 发布：从 release 安装到干净测试环境，核对实际加载的内容，不用源码目录的通过结果代替安装验收。

## 10. 评分

这是基于本次代码与证据的工程判断，不是代码覆盖率、安全认证或用户满意度统计。

| 维度 | 分数（10 分制） | 权重 | 理由 |
| --- | --- | --- | --- |
| 产品定位与痛点匹配 | 8 | 15% | 细分价值明确，历史/一致性方向成立 |
| 架构与可维护性 | 6 | 15% | 有良好分层意图，但入口/解析/状态规则重复 |
| 核心流程正确性 | 6 | 20% | GitHub/命名空间较扎实，GitLab与历史存在重要缺陷 |
| 并行执行完整性 | 2 | 15% | 有基础设施，没有可靠真实执行和汇合闭环 |
| 四端覆盖与降级 | 5 | 10% | 多入口已有，桌面概念混淆、路由和验收不一致 |
| 测试质量 | 6 | 15% | 回归与反例投入明显，但关键用户旅程缺失 |
| 发布与文档可信度 | 4 | 10% | 安装/main 不一致，部分完成和支持范围表述过强 |

**加权综合：54/100。** 不是方向只有 54 分，而是当前版本距离你要求的“可靠、四端清晰、可愉悦持续迭代”的交付标准仍有差距。最值得投入的是把现有流程做实，而不是马上扩大功能范围。

本次按代码审查 skill 的多轴方法，将契约、可靠性、测试与维护成本分别评估，因此没有只看功能数量或通过断言数打分。审计未修改插件实现，也未执行发布、推送或远端业务写入。
