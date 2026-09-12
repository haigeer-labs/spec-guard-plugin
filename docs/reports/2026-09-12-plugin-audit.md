# Spec Guard 插件整体审查报告

## 元数据

- 审查日期：2026-09-12
- 基线：`v0.11.0`（`6c84f19`）
- 范围：功能价值、端到端闭环、数据安全、tracker 边界、测试与发布证据
- 外部边界：未操作真实 GitLab；所有 GitLab 行为复现均通过本地 `glab` 桩完成。未创建远端 issue、MR 或 release。早期已安装副本的 smoke 以退出码 2 表示无法证明 hook 执行，未记为验收；随后以独立候选插件 ID 安装当前 worktree 并在临时本地仓库运行 smoke，退出 0。GitHub Actions 做过只读查询，并在用户明确授权后尝试 dispatch；GitHub 以 HTTP 422 拒绝，未生成或重跑 workflow。
- 结论状态：基线审查已完成；修复批次 `write-safety-remediation` 已完成 R01–R05、R08、R11 的本地实现与定向回归，尚未发布。

## 结论与评分

当前评分为 **35/100（不建议作为稳定工作流全面启用）**。

插件的核心定位有实际价值：它补足了上游 agent-skills 在多模块 spec、计划命名空间和 tracker 连接上的断点。阶段提示、映射校验、能力历史与多宿主适配也已有可复用的基础。

但产品尚未完成安全收口：多条本地文件写入路径会在畸形输入或拼写错误时“报成功但保留错误状态”，生命周期可越出项目目录写入或删除，GitLab bridge 的写操作没有强制确认。测试和发布证据也不足以把这些能力称为稳定可用。

评分口径：核心问题价值 18/20，设计边界 10/20，功能闭环 5/20，安全与数据完整性 0/20，验证与发布可信度 2/20。

整改工作树的暂定评分为 **67/100（可作受控源码候选，仍不建议发布为稳定版本）**：核心问题价值 18/20、设计边界 11/20、功能闭环 13/20、安全与数据完整性 17/20、验证与发布可信度 8/20。该分数反映本地源码、回归及一次已绑定候选来源的真实 Codex 宿主 smoke；没有命名发布 artifact、CI 运行或真实 GitLab 验收，不能把它表述为线上质量结论。

## 已验证的功能价值

| 功能 | 评估 | 结论 |
| --- | --- | --- |
| 多模块 spec/plan 命名空间 | 高 | 直接解决上游多模块产物覆盖，保留为核心能力。 |
| tracker 映射与阶段提示 | 中 | 方向正确，但 archive 与 tracker 真相可漂移，不能独立判定完成。 |
| 映射/历史/文档核验 | 中 | 适合作为只读诊断与证据工具；历史摘要不能替代实际交付事实。 |
| GitLab 支持 | 低（修复前） | 本地桥接有价值，但写操作的确认和幂等性不足。 |
| 并行与桌面 worker | 实验性 | 尚不构成可稳定交付的端到端能力，不应按核心功能宣传。 |

## 发现的问题与建议顺序

| ID | 优先级 | 发现 | 用户影响 | 收口条件 |
| --- | --- | --- | --- | --- |
| R01 | P1 | setup/teardown 仅定位首个 BEGIN 与最后一个 END；缺失或重复标记会吞掉标记外内容，且异常仍可能报告成功。 | 用户的 CLAUDE.md/AGENTS.md 内容可被误删；hook 可能仍激活。 | 标记必须恰好一对、顺序正确；任一畸形状态零写入且非零退出；双宿主均有回归。 |
| R02 | P1 | teardown 和 setup 对未知或畸形参数静默忽略。`--dry-run=true` 可实际执行拆除。 | 用户以为预览，实际改变文件与 state。 | 未知、重复、带值或冲突参数在任何写入前退 2；测试证明文件逐字不变。 |
| R03 | P1 | initiative lifecycle 先拼接/创建归档路径，后验证 initiative/module id；state 的异常 module key 可参与删除。 | 可在项目外留下归档残留，或删除项目内非模块文件。 | 所有输入、所有目标路径与 state/map 对应关系先验证；失败零写入零删除；路径逃逸、绝对路径、异常 state 均回归。 |
| R04 | P1 | gitlab bridge 的 issue、relation、MR、merge 直接执行 `glab` 写操作。 | 缺少代码级授权闸，文档确认不能阻止误调用。 | 四类操作都必须显式 `--confirm`；未确认不调用 glab；本地桩覆盖成功与拒绝。 |
| R05 | P1 | 本地 archive 可与远端 tracker 的 open issue 脱节。 | phase/历史显示完成，但真实工作尚未收口。 | 对 completed 归档读取快照中的 tracker；只有用户在运行时显式设置 `SPEC_GUARD_ARCHIVE_REMOTE_VERIFY=1` 才读远端。远端 OPEN 显示分歧，读取失败或未授权明确待核验，只有 CLOSED 才显示“远端已核验”。 |
| R06 | 已复核 | 实验性并行写入口已统一返回 `PARALLEL_WRITES_DISABLED`；旧 run/worker 仅可只读核验，旧 `completed` 显示为 `unverified`。 | 自动并行目前不可用，但不会再由插件创建、领取、汇合或回收资源。 | 保持暂停，不作为稳定功能宣传；未来重启前须另立模块，完成真实宿主 E2E、身份、互斥、汇合与回收验收。 |
| R07 | 已复核 | 当前 `test-sync-map-gitlab.sh` 覆盖重复同步复用、丢失 create 响应恢复、歧义/过期 state 拒绝与 preview 零写入。 | 本地桩证据不等于真实 GitLab 发布验收。 | 无新增代码修复；发布前仍需在获授权的隔离项目验证。 |
| R08 | P2 | MCP serverInfo 版本固定为 0.8.0，与 v0.11.0 manifest 不一致。 | 诊断与安装版本信息不可信。 | 从唯一 manifest 来源读取版本，并加入一致性测试。 |
| R09 | 部分收口 | `v0.11.0` 有 changelog，但 `docs/releases/` 没有对应的命名发布 artifact/安装记录。本机两个旧同名插件的 smoke 均不作为证据；当前 worktree 已以独立候选插件 ID 安装，带 `--plugin-id`、`--expected-source` 的 smoke 退出 0，且缓存与当前源码（排除 Codex 自动生成目录）一致。README 所称“尚未发布”仅指当前整改分支，不构成版本冲突。 | 当前候选的 hook 注入已得到真实宿主验证，但还不能追溯证明正式 `v0.11.0` 发布体验。 | 为命名 artifact 补充干净环境安装记录，并补充 CI 实际运行。 |
| R10 | 外部阻塞 | 本地与远端均有 active 的 `.github/workflows/validate.yml`（远端 workflow ID `342899601`），覆盖 Ubuntu/macOS 的 `scripts/validate.sh` 与关键回归；只读查询显示 `Validate` 历史运行数为 0。获用户授权后尝试 workflow dispatch，GitHub 返回 HTTP 422：`Actions has been disabled for this user`，未生成 run。本地 `scripts/validate.sh` 已通过，但变异测试因当前被修改文件跳过。 | 本地“全绿”无法等同发布保证；当前账号无法生成 CI 证据。 | 由具有 Actions 权限的仓库管理员启用/授权该账号后触发一次实际 CI，并让变异测试在独立 checkout/worktree 运行。 |
| R11 | P1 | phase hook 会为识别自建 GitLab remote 自动执行 `glab repo view`。 | 每次提示注入都可能在未授权情况下访问真实 GitLab。 | 自建实例只接受 `.agent/state.json` 的显式 `tracker=gitlab`；自动识别仅做不联网的 `gitlab.com` host 判断。 |

## 本轮修复范围

本轮实现 R01–R05、R11 的最小安全收口，顺序为：声明块解析 → 参数拒绝 → lifecycle 预检 → GitLab confirm gate → archive/tracker 显式授权的只读对账 → 自建 GitLab 的无联网识别。每一步先写能在旧行为失败的本地回归，再实现最小修复。复核同时确认 R06 已通过“暂停写入口”的方式安全收口；R09、R10 保留为后续独立模块，避免扩大本次改动或把未验证的外部流程伪装成已完成。

### 本地收口证据（未发布）

| 条目 | 本轮状态 | 证据 |
| --- | --- | --- |
| R01 | 已实现 | 共享原子声明块解析器要求唯一、顺序正确的一对标记；缺失/重复 END 的 setup 与 teardown 均验证零写入。 |
| R02 | 已实现 | setup/teardown 拒绝未知、重复与冲突参数；`--dry-run=true` 不再被当作有效预览。 |
| R03 | 已实现 | lifecycle 规范化项目根、先验证 initiative，模块只取能力图；越界 state module 和 initiative 回归均证明无删除、无项目外残留。 |
| R04 | 已实现 | issue、relation、MR、merge 必须在 action 后显式给出 `--confirm`；缺失时本地桩记录为零调用。 |
| R05 | 已实现（显式授权的只读诊断） | completed 归档从历史快照读取 initiative tracker；默认不访问远端并标记 `ARCHIVED (远端待核验)`。仅在运行时显式设置 `SPEC_GUARD_ARCHIVE_REMOTE_VERIFY=1` 时，GitHub/GitLab 为 OPEN 才进入 `ARCHIVE_DRIFT`，不可读保持待核验，只有 CLOSED 才显示“远端已核验”。lifecycle 不联网，仍可离线安全归档。 |
| R06 | 已复核 | `parallel-execute`、`parallel-integrate`、`parallel-reclaim`、CLI 启动与 Desktop 登记均拒绝写入；三组旧记录/CLI/Desktop 本地回归证明拒绝不改现有资源。 |
| R08 | 已实现 | MCP `serverInfo.version` 由同一份 `manifest.json` 提供，初始化响应与 manifest 的一致性有回归。 |
| R07 | 已复核 | 当前 fake-glab 幂等/恢复回归 6/0 通过；保留真实 GitLab 验收为发布前的授权项。 |
| R11 | 已实现 | 自建 GitLab remote 在未声明 tracker 时退回本地模式，且本地桩证明 hook 对 `glab` 零调用；显式 `tracker=gitlab` 的现有工作流不受影响。 |
| R09 | 已部分验证 | 独立 ID `spec-guard@spec-guard-audit-candidate` 曾从当前 worktree 临时安装；指定该 ID 与候选目录的真实 Codex smoke 退出 0，收到 hook 注入的当前阶段事实。缓存与源码一致（排除 Codex 自动生成的 `migrated-command-skills`）。验收后已移除该临时插件与 marketplace，稳定版和 RC 未改动。 |

本轮定向验证：phase/setup/teardown 156/0（GitHub/GitLab 均为本地桩，包含无 module spec 的正常归档、缺失快照降级、默认 GitHub/GitLab 零远端调用和自建 GitLab 零 `glab` 调用）、lifecycle 8/0、artifact-history 8/0、GitLab bridge、Codex adapter 与 local-context 均通过；parallel CLI、Desktop 登记与旧 ledger 三组回归均确认写入口暂停。完整本地 `scripts/validate.sh` 已于 2026-09-12 再次退出 0；其中 Codex smoke 只跑判决器 `--selftest`，未调用 Codex，mutation-check 因已修改的 `phase-guard.sh` 跳过，均不构成真实宿主或 CI 证据。真实 smoke 的判决器额外校验唯一插件 ID 与 source：多个同名安装或来源不等于候选目录均返回退出 2，绝不把旧安装副本记为本次通过。对当前候选，`spec-guard@spec-guard-audit-candidate` 的 smoke 退出 0，收到有效的当前阶段注入；缓存内容与当前 worktree 一致（排除 Codex 自动生成目录）。

## 修复后的复评门槛

完成 R01–R05、R08、R11 且所有定向/全量回归通过后，可将“数据安全与确认”从 0/20 提升为有条件评分；但只有补齐真实安装验证与 CI 证据，才应重新评估是否进入稳定发布。并行能力在恢复写入口前始终按“暂停的实验能力”计，不得纳入稳定发布承诺。
