# Spec Guard Worktree 执行器：建议设计（未实施）

状态：研究结论后的设计提案；不代表已批准或已实现。
前提：见 [研究源报告](report-source.md)。

## 目标与非目标

目标是在能力图经现有 `parallel-readiness` 和 `parallel-safety-gate` 判定后，让**不同模块**在
隔离 Git Worktree 中并行开发，同时保持任务排重、可恢复、可审计和逐个汇合。

第一期不做：跨 clone 的强互斥、同一模块的并行写入、自动合并、后台 Desktop UI 自动化、远端/
Cloud 透明支持，或把现有只读并行命令变成写入命令。

## 新的显式工作流

```text
/parallel-readiness (既有，只读)
→ /parallel-safety-gate (既有，只读)
→ 用户确认 /parallel-execute
→ 控制器建立 run + module leases
→ 宿主适配器 provision Worker
→ Worker 基线校验后实现
→ /parallel-status 汇总
→ 用户确认逐个 /parallel-integrate
→ /parallel-reclaim（仅 controller-owned worktree）
```

`/parallel-guidance` 保持人工指引；`/parallel-subagent-preflight` 保持只读，不能悄悄升级为
写入 Worker。

## 数据边界

### Canonical state 与 Worker state

| 数据 | 位置 | 原因 |
| --- | --- | --- |
| Capability map、模块 spec、现有 `.agent/state.json` | 版本库工作树 | 继续是现有设计/Tracker 投影事实 |
| run、worker、lease、宿主 id、绝对路径、基线、所有权 | `git rev-parse --git-common-dir` 下的 `spec-guard/parallel/v1/` | 同一 clone 的所有 linked worktree 可见，不进入 PR，不与业务文件合并冲突 |
| 每个 worker 的宿主运行时信息 | 同一 common-dir 账本的 `workers/<id>.json` | 允许失败恢复和所有权判断 |

不能让多个 worker 各自修改 `.agent/state.json.activeModule`：这些变更会在各模块 PR 中冲突，且
其中一个分支的“下一个模块”不能代表整个并行 run。worker mode 中，`activeModule` 仅作被读取的
旧版兼容输入；实际目标 module 从受控 worker manifest 取得。主 checkout 只在所有模块已汇合后
由控制器一次性推进生命周期。

### Identity、lease 与原子性

```text
runId = sha256(normalizedRemote + baseSha + capabilityMapGoalDigest + orderedModuleRowDigests)
workerId = <run-short>-<module-id>-<attempt>
```

同一 Git common-dir 内，创建 `leases/module-<module-id>/` 必须为原子操作；成功者写 owner、PID/
host task id、开始时间、TTL、base SHA。第二个调用得到结构化 `CONFLICT`，不执行 `/next`。

同一电脑的不同 worktree 因共享 common-dir 而可获得这项保护。不同 clone 没有共享原子目录：第一期
显示 `crossClone=unverified` 并禁止自动写入，或要求未来单独接入具有 compare-and-set 的远端
lease 服务。GitHub/GitLab Issue 的 assignee/评论/label 不算 lock。

## 控制器合同

### Provision contract

每个 adapter 成功前必须返回：

```json
{
  "worktreePath": "absolute path",
  "gitCommonDir": "absolute path",
  "head": "full SHA",
  "branch": "name | null for detached",
  "host": "codex-cli | claude-cli | codex-desktop | claude-desktop",
  "hostWorkerId": "stable ID if provided",
  "owner": "spec-guard | host",
  "state": "provisioned"
}
```

控制器随后验证：路径真实存在、Git common-dir 等于 run 所属仓库、HEAD 等于记录基线或合规的
worker branch、不是误判的 submodule、目录干净、setup 成功、基线测试成功。否则释放 lease 或标为
`unknown`，绝不让 worker 写代码。

### Worker contract

worker prompt 必须包含 runId、workerId、唯一 module id、base SHA、边界、禁止触碰的模块和
“只允许使用本 worker manifest”的规则。Worker `/next`：

1. 验证自身 lease 仍活跃；
2. 只从 manifest 的 module Issue / plan 找 task；
3. 取得 task 子 lease；
4. 不推进 `.agent/state.json.activeModule`，不关闭 initiative；
5. 所有提交和 PR/MR 都写 runId、module id、task ID。

这替代当前“当前分支完成 task + `activeModule` 线性推进”的局部假设，仅在 worker mode 生效。

### 汇合与回收

- 每个 module worker 仍是一个模块、一个分支、一个 PR/MR；不能让多个 worker 写一个 module。
- 控制器只在 PR/MR、基线、模块测试和分支基线都核验后标记 `ready_to_merge`。
- 汇合是用户确认的**逐个**操作；每次合并后，在新默认分支上重跑必要测试，再处理下一项。
- `owner=spec-guard` 的 worktree：只有合并成功或显式 discard 后才可移除；顺序固定为
  merge/test → `git worktree remove` → 删除分支 → `git worktree prune`。
- `owner=host` 的 Desktop worktree：插件只能更新“可回收”状态与标题/提示；由宿主归档策略回收。
- PR/MR 创建后默认保留 worktree，不能自动删除。

## 四个 adapter

| Adapter | 创建方式 | 自动程度 | 发布前证据门槛 |
| --- | --- | --- | --- |
| `codex-cli` | controller `git worktree add -b`，再 `codex -C` | P0 全自动 | 临时 Git repo E2E：create、cwd、lease、失败、cleanup |
| `claude-cli` | controller 自建后在该 cwd 启动，或 Claude `-w` 后登记 | P0 全自动 | CLI E2E；不可嵌套 `-w` |
| `codex-desktop` | 用户在 UI 创建原生 project Worktree task，插件用 `/parallel-register-worker` 登记 | P1 register-only | cwd/common-dir/HEAD 与 worker manifest 通过；不要求也不尝试插件创建 Desktop task |
| `claude-desktop` | 原生 isolated session/worker；运行时登记 | P1 实验性 | 实际 Desktop session + isolated worker E2E；确认 plugin 能力、cwd、回收 |

Desktop 的创建者是宿主而非 controller。这样保留用户能看见的会话、标题、归档和 snapshot；若未经
验证就改用 `git worktree add`，会产生 Desktop 看不见的 phantom worker，不进入 P1。

## 宿主缺失能力时的统一降级

```text
adapter 不存在 / native API 不可见 / worktree 未就绪 / 无稳定 worker ID
→ 不领取 lease，不执行写入
→ 输出 worker manifest、推荐命令或 Desktop 操作步骤
→ 用户手工启动后运行 /parallel-register-worker
→ 所有 runtime assertions 通过后才转 running
```

因此体验可能不同，但安全语义一致；不会因“桌面端没有 API”退回到共享目录并行写入。

## 与现有流程的改动边界

1. 增加新命令和新的控制器脚本，不更改既有只读命令的输出契约。
2. 现有非 parallel workflow、现有 `.agent/state.json` schema、GitHub/GitLab bridge 保持不变。
3. worker-aware `/next`、`/deliver` 必须在检测到有效 manifest 时才启用；普通项目继续走原逻辑。
4. worker manifest 的 schema 必须版本化；未知版本 fail-closed。
5. 任何自动创建 Desktop task、标题更新或归档都要求用户在执行时明确确认，不能借由
   `manual-parallel-eligible` 自动触发。

## 分阶段验收

### Gate 0：设计验证

- Git linked-worktree/submodule 检测单测；
- common-dir 原子 lease 单测；
- base SHA、branch、cwd 不一致拒绝；
- 并行 worker 不改 canonical `state.json` 的回归测试。

### Gate 1：CLI

- 两个不重叠 module 两个 worktree，同时写入与测试；
- 同一 module 第二 worker 被拒绝；
- setup/test 失败、agent 退出、lease 过期、恢复 unknown；
- merge order、PR 保留、discard 确认和 owned-only cleanup。

### Gate 2：Codex Desktop（register-only）

- 用户在 UI 创建的自然 Worktree task 结果从 pending 到可读 thread id；
- cwd/common-dir/HEAD 的三项实证；
- 标题状态迭代、handoff、archive/snapshot 和 Desktop owner 回收；
- 当前公开 App Server 只有 `cwd`，没有 managed-worktree 创建字段；测试 fail-closed 的手工
  register 路径，且不得回退为 controller 自建的 Desktop phantom worker。

### Gate 3：Claude Desktop

- 两个 parallel session 与实际 worktree；
- Worker isolation 是否可由插件路径触发；
- session 中断、恢复、归档的 registry 一致性；
- 原生能力缺失时不发生 nested/phantom worktree。

## 设计结论

建议批准的下一步仅为 **P0 CLI-only prototype 的正式 spec**。Desktop adapter 在 Gate 2 / Gate 3
完成前维持实验性、用户显式确认和手工登记 fallback。这样可以先获得真实的多 worker 控制器，而
不会用未证实的桌面 API 把插件设计锁死。
