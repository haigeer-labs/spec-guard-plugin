# Worktree 并行执行器：前置实测与架构审计

日期：2026-09-04
读者：Spec Guard 维护者
范围：Codex CLI / Codex Desktop / Claude Code CLI / Claude Code Desktop，以及
`obra/superpowers`（用户口述的 “Superflow” 按此项目审计）。
结论用途：决定是否进入正式需求设计；不是实现规格，不授权修改插件。

## 直接结论

可以实现一个跨宿主的 **Worktree 执行控制面**，但不能声称四个宿主都能由插件以相同方式
自动创建、展示和回收原生会话。

- **CLI 后端**可由控制器完整管理：创建 Git linked worktree、创建分支、验证基线、在该目录
  启动 Worker、收集结果、在确认后清理。
- **Codex Desktop**已实证使用真实 Git linked worktree；但当前 `codex app-server` 的公开
  `ThreadStartParams` 只有 `cwd` 等通用线程字段，没有 `worktree`、起始分支或 managed-task
  创建字段。因此插件不能把本研究对话可见的宿主控制接口写成发布契约。首版只能登记用户在
  Desktop UI 创建的原生 Worktree；自动创建须等待公开、可由插件调用的 API。
- **Claude Code Desktop**原生自动隔离并行 session；其运行时支持将主会话进入新建/已有
  worktree，且有 subagent isolation 机制。但没有公开的插件 API 用于静默创建任意 sidebar
  session。必须能力探测并保留 fail-closed 降级。
- **Superpowers**不是成熟的并行写入 Worker 控制器。其当前主线只是提示 Agent 手工创建一个
  worktree；不能直接接管。

正确的产品边界是：Spec Guard 拥有 **identity、租约、worker manifest、基线、验证、汇合和
回收决策**；每个宿主适配器拥有其可验证的 **worktree / 会话创建方式**。

## 范围、假设与成功标准

假设所有本地执行场景都有 Git 仓库；Cloud/Remote、非 Git VCS、跨机器 clone 不是第一期自动
写入范围。GitHub/GitLab 仍为现有 tracker，不能把 assignee、comment 或 label 冒充互斥锁。

第一期成功必须同时满足：

1. 两个经 safety gate 判定可并行的模块在独立 linked worktree 运行，cwd、HEAD/branch、基线
   SHA 都可审计。
2. 同一 initiative/module 不能被两个本机 Worker 同时领取；不能保证跨 clone 时必须明确降级。
3. 当前单 `activeModule` 仅表示**单个 Worker checkout**的焦点，不承担全局调度；全局状态放在
   控制器账本。
4. worker 不能自行推进别人的 `/next`、关闭别人的 module/initiative 或清理非自己创建的
   worktree。
5. 失败、超时、测试失败、Desktop 原生能力缺失均停止写入，保留可恢复证据。

## 实测证据

### Codex Desktop

1. 当前 Codex App 的项目列表中，`spec-guard-e2e-parallel` 是 Git 项目，可作为隔离测试项目。
2. 当前任务列表已有 Codex managed worktree：
   `/Users/vilin/.codex/worktrees/7c0f/sentinel-video-scaffold`。
3. 对其真实仓库执行 `git worktree list --porcelain`，能得到该目录；在该目录执行
   `git rev-parse --git-dir` 得到
   `/Users/vilin/Documents/gs/sentinel-video-scaffold/.git/worktrees/sentinel-video-scaffold1`，
   `--git-common-dir` 得到主仓库 `.git`。这证明它是 linked worktree，不是目录复制品。
4. 同一真实项目还存在一个 Codex managed worktree 处于 detached HEAD，说明官方所述的默认
   detached 模型在本机有实例；也存在后来创建了命名分支的 managed worktree。控制器不能假设
   所有 Desktop worker 都有分支。
5. 用当前宿主的创建接口请求一个只读 Worktree 测试任务，接口返回了
   `client-new-thread:b76bc304-3122-4066-a175-8a7a490a2ae0`，而非可操作 `threadId`。此后约
   90 秒内，该任务未在 `list_threads` 可见。该结果只证明请求进入异步 setup，**不证明创建
   成功**；也表明控制器必须处理 `pending`、超时和无 threadId 的状态，不能在收到 client id 后
   就领取模块或写入 lease。
6. 本机 `codex-cli 0.150.1` 生成的最新 App Server JSON schema 中，`ThreadStartParams` 的字段为
   `approvalPolicy`、`approvalsReviewer`、`baseInstructions`、`config`、`cwd`、
   `developerInstructions`、`ephemeral`、`model`、`modelProvider`、`personality`、`sandbox`、
   `serviceName`、`serviceTier`、`sessionStartSource`、`threadSource`；没有 worktree、branch 或
   starting-state 字段。这证明公开 App Server 只能在**既有目录**启动通用线程，不能按指定基线
   provision Codex Desktop managed worktree。它可用于登记/附着已有 worktree，不能作为插件自动
   创建 Desktop task 的依据。

官方资料确认新聊天可选择 Worktree 与起始分支；Desktop 创建实际 Git worktree，默认 detached
HEAD，归档 managed chat 后可自动回收目录并保留 snapshot。
[Codex Worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees)

### Codex CLI

本机 `codex-cli 0.150.1` 的 `codex --help` 与 `codex exec --help` 有 `-C/--cd`，没有
`--worktree`。因此通用执行链是：

```text
git worktree add <path> -b <branch> <base>
→ 基线 setup/test
→ codex -C <path> … 或 codex exec -C <path> …
```

这是可完整自动化的后端；但 worker 进程、权限、日志和清理仍须由控制器记录，不能只凭目录名。

### Claude Code

- 本机 `claude 2.1.259` 的 help 确认 `-w, --worktree [name]`。
- 官方 CLI 文档说明 `claude --worktree` 在
  `<repo>/.claude/worktrees/<name>` 创建隔离 checkout 与分支。
  [Claude CLI reference](https://code.claude.com/docs/en/cli-usage)
- Claude Desktop 文档说明多个并行 local Code session 使用独立 Git worktree，默认目录为
  `<project-root>/.claude/worktrees/`，归档 session 可回收其 worktree。
  [Claude Desktop](https://code.claude.com/docs/en/desktop)
- Claude 工具文档将 `EnterWorktree` 定义为“创建隔离 Git worktree 并切入当前主会话”，也可切入
  当前仓库已有 worktree；该工具不能用于 subagent。
  [Claude tools reference](https://code.claude.com/docs/en/tools-reference)
- Claude 官方并行文档把 worktree、subagent、agent view、agent team 视为不同机制：Agent team
  不会为 teammate 自动做 worktree 隔离，不能把“有 team”误写为“安全的并行写入”。
  [Run agents in parallel](https://code.claude.com/docs/en/agents)

## Superpowers 审计

当前本机 `origin/main` 为 `917e5f53`。它的
[using-git-worktrees](https://github.com/obra/superpowers/blob/917e5f53b16b115b70a3a355ed5f4993b9f8b73d/skills/using-git-worktrees/SKILL.md)
是 Agent 工作流程文本，而非可执行控制器：

1. 优先寻找 `.worktrees/`、`worktrees/`、再看 `CLAUDE.md`、最后询问用户；
2. 对项目内目录必须 `git check-ignore`，避免把 worktree 文件误纳入 Git；
3. `git worktree add <path> -b <branch>`；
4. 自动探测依赖安装；
5. 跑干净基线测试；
6. 在收尾前再跑测试，随后按用户选择 merge/PR/保留/discard。

值得借鉴的是“目录选择 → ignore 验证 → setup → 基线测试”的顺序，不是其文本本身。

不应借鉴或误解的部分：

- [subagent-driven-development](https://github.com/obra/superpowers/blob/917e5f53b16b115b70a3a355ed5f4993b9f8b73d/skills/subagent-driven-development/SKILL.md)
  明确禁止并行派发多个 implementation subagent；它是串行 implement → spec review → quality
  review。
- [dispatching-parallel-agents](https://github.com/obra/superpowers/blob/917e5f53b16b115b70a3a355ed5f4993b9f8b73d/skills/dispatching-parallel-agents/SKILL.md)
  仅支持独立调查/故障域 fan-out，不创建 worktree、分支、lease、汇合队列或回收器。
- 当前
  [finishing-a-development-branch](https://github.com/obra/superpowers/blob/917e5f53b16b115b70a3a355ed5f4993b9f8b73d/skills/finishing-a-development-branch/SKILL.md)
  对 PR 后是否清理 worktree 的文字有矛盾，不能原样复用。

有一个未合入 main 的参考设计
[PRI-974](https://github.com/obra/superpowers/blob/2d446f0610fc52b5099abdc59b9b82b37f981f79/docs/superpowers/specs/2026-04-06-worktree-rototill-design.md)：
它提出 linked-worktree 检测、原生宿主工具优先、手工 fallback、创建者负责回收和统一基线验证。
这是很好的模式来源，但不是发布能力；其测试也主要验证 Agent 的命令选择，不是多 worker 的
真实生命周期测试。

## 统一控制面与四个宿主适配器

### 控制器必须做的事情

控制器不是现有 `.agent/state.json` 的字段扩展，而是独立账本，至少包含：

```text
initiativeIdentity = normalizedRemote + baseSha + capabilityMapDigest
workerId           = initiativeIdentity + moduleId + attempt
owner              = spec-guard | codex-desktop | claude-desktop | user
state              = pending | provisioned | running | blocked | ready_to_merge |
                     merged | reclaimable | released | failed | unknown
baseSha, branch, worktreePath, host, hostWorkerId, lease, timestamps
```

本机同一 Git common-dir 中，声明 lease 必须用原子操作（例如创建唯一目录或独占文件），而不是
“先检查、再写入”。不同 clone 必须使用真正具备 compare-and-set 语义的远端协调器；GitHub/GitLab
Issue assignee、评论和 label 都只能提供提示，不能提供排他保证。

`state.json` 仍可在每个 worker worktree 内保持单一 `activeModule`，因为它只服务当前 worker。
控制器账本才保存并行集合；不把多活跃模块塞进现有 tracker state，避免破坏 `/next` 和 lifecycle。

### 适配器合同

| 宿主 | Provision | 启动/绑定 | 回收权 | 第一期开关 |
| --- | --- | --- | --- |
| Codex CLI | 控制器 `git worktree add` | `codex -C` | 仅 `owner=spec-guard` | 支持 |
| Claude CLI | 控制器建 WT 后在该目录启动；或宿主 `-w` 后登记 | shell cwd / Claude native | 谁创建谁回收 | 支持 |
| Codex Desktop | 用户在 UI 创建原生 project Worktree task，插件登记 | task id + cwd/HEAD 证明 | Desktop 管理；插件只标记可回收 | register-only（P1） |
| Claude Desktop | 原生隔离 session / 支持时的 isolated worker | session/worktree 运行时登记 | Desktop 管理；插件只标记可回收 | 实验性 |

适配器的共同后置条件：

```text
实际 worktree 路径存在
→ cwd 位于该路径
→ 当前 HEAD 与记录的 baseSha/worker branch 相符
→ linked-worktree 检测通过（同时排除 submodule 误判）
→ 项目 setup 完成
→ 基线测试通过
→ 原子领取 module lease
→ 才允许写代码或运行 /next
```

任一条件失败均为 `failed` 或 `unknown`，不应自动转给另一 worker。

## 与现有 Spec Guard / 上游的冲突边界

1. 现有 `parallel-readiness`、`parallel-safety-gate` 和 `parallel-guidance` 明确承诺只读、不创建
   worker。这些命令的现有语义不能悄悄改变；应新增显式、用户确认的执行命令。
2. 现有 GitHub `/next` 按当前 worktree 的 `activeModule` 选 task，且“读取 → 选择 → assign”不
   原子；GitLab `/next` 没有 claim。控制器 lease 必须在调用它们之前取得，否则同 initiative 的
   worker 会重复任务。
3. 现有每模块一个分支/PR 的交付契约与多 worker 同时修改同一模块冲突。第一期只允许一模块一
   worker；不同模块只有在 safety gate 证明边界不重叠时并行。汇合仍逐个执行。
4. GitHub/GitLab 分别仍是 Issue/MR tracker，不承担本地 worker 调度；离线 hook 不能被改成网络锁。
5. Superpowers current-main 也禁止并行 implementation worker，故不能宣称继承其并行执行能力。

## 推荐实现顺序与未解决项

### P0：先做 CLI-only prototype

新增独立 `parallel-executor` 控制器和只读 `parallel-status`；仅 `spec-guard` 自建 worktree 的
Codex CLI 后端可启用。覆盖 create、重复 lease、失败 setup、失败基线、cwd/branch 不匹配、完成
保留、显式回收、恢复 unknown worker。绝不默认开启。

### P1：验证 Desktop 原生适配器

对每一个 Desktop 做真实 E2E，而非只测 Skill 文本：

1. 创建 worker → 获得稳定的宿主 worker id；
2. 读取 task cwd、Git common-dir、HEAD/branch、基线 SHA；
3. worker 只读检查、单模块提交、测试；
4. 测试两 worker 不同模块并行、同模块 lease 拒绝；
5. 中断/失败后恢复；
6. PR/MR 后保留；归档/用户确认后清理；
7. 验证插件运行路径能调用的能力，而不是本研究对话的特权工具。

Codex 当前创建探针仍处于未解析的 pending client id；同时最新公开 App Server schema 未提供
managed-worktree 创建字段。因此 P1 的自动创建不应继续作为待测功能，而应降级为 register-only；
只有未来出现公开、插件可调用的创建 API，才重开自动创建 E2E。

### 不建议实现的方案

- 在 Desktop 已有原生 Worktree 时，插件自行另建“phantom” worktree，再假装有 Desktop worker。
- 把 native `spawn_agent` 当作隔离写入 worker。
- 用 Issue assignee 作锁，或只用目录/分支名判断所有权。
- 未跑基线测试就启动写入 worker。
- PR/MR 创建后自动删除仍可能需要修复的 worktree。

## 停止条件与限制

已取得足以决定架构方向的本机命令、现有 managed worktree、当前 CLI 和一手源码证据；继续阅读
重复文档不会改变结论。尚未通过的 Desktop 自动创建 E2E 及插件调用权不能被推断为成功，保留为
正式设计前的阻断项。
