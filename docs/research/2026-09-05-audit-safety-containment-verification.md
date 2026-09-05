# audit-safety-containment 增量验证记录

状态：LOCAL VERIFIED。首模块实现与本地验收已通过，待模块 PR；未推送、合并或发布。
以下 T1–Checkpoint B 段落是当时的增量记录；最终范围及证据见末尾 T11 / Checkpoint C。

## 2026-09-05：映射与 T1 / Issue #144

- 基线：`c2f247ce5b76fe87887206b0761ef8d16a17ea98`；本地分支 codex/fix/audit-safety-containment。
- GitHub：initiative #138 的子模块为 #139–#143，module #139 的任务为 #144–#157。REST sub_issues 与逐项 blocked_by 核验数量、顺序和依赖全部一致。
- `.agent/state.json` 与能力图 digest check：ok=true，5/5，missing/extra/rowsStale 为空，goalStale=false。
- T1 仅修改三个测试脚本并新增测试专用夹具；没有改生产运行时或指纹算法，没有启动真实 Agent。

### 测试证据

1. 修改前三套 ledger/worktree/CLI 回归全部退出 0。
2. RED：CLI 测试切换到独立 fixture 接口后，因 test_parallel_fixture 尚未实现而退出 1；这是新接口缺失，不声称复现了生产缺陷。
3. GREEN：实现 fixture 后，三套回归全部退出 0。worktree fixture 对缺失目录、错误 branch 和错误 HEAD 的反向输入均拒绝。
4. `/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh`：129 通过 / 0 失败。
5. `/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh`：72 通过 / 0 失败。
6. `/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh`：10 通过 / 0 失败。
7. `/bin/bash evals/codex-plugin-smoke.sh --selftest`：退出 0，正确区分通过、行为失败和环境未就绪；不等于真实宿主 E2E。
8. `/bin/bash scripts/validate.sh`：工作区首跑失败；test-checkers 会临时改 spec-digest.py，再用 Git 恢复，后者被沙箱拒绝。已只撤销该测试注释，没有改算法。将相同测试差异与新增 fixture 应用到独立本地 clone 后重跑退出 0。

独立 clone 与完整 validate 日志位于 `/private/tmp/spec-guard-containment.RZ9G4D`，日志文件 `validate.log`。该路径是本机临时证据，可能被清理；本记录保存结果摘要，后续模块交付还需最终版本的持久化验收证据。

### 剩余边界

生产 create/claim/provision/start/register/reclaim 仍未禁用；其原有行为断言按计划保留，待对应任务变更契约。只读场景的夹具已可独立构造，生产创建行为测试尚须调用生产入口。

没有向默认分支合并或发布，Issue #144 应在模块交付合并后才由提交 closing keyword 关闭。后续从 #145 继续，不把 T1 计为 F01–F04/F09/F10 已缓解。

## 2026-09-05：T2 / Issue #145

- `parallel-execution.py create-run` 与 `claim-module` 在解析项目路径、读取 safety report 或 ledger 前统一拒绝，稳定返回 `PARALLEL_WRITES_DISABLED`；JSON 模式只输出一份结构化错误。
- 共享的 `claim_lease` 也在所有输入校验和文件写入前拒绝，因此不能从库调用绕过 CLI 边界。通用 `write_json_exclusive` 没有被改成全局禁用，以免破坏只读状态夹具和无关的安全写入场景。
- 新增 `test-audit-safety-containment.sh`，覆盖 create、claim、direct lease 及两个 CLI 入口：每个拒绝场景都验证 ledger 父目录保持不存在、无 stderr 污染 JSON 输出。

### 测试证据

1. `test-audit-safety-containment.sh`、`test-parallel-execution-ledger.sh`、`test-parallel-worktree-runtime.sh`、`test-parallel-cli-execution.sh`、`test-parallel-workflow-integration.sh`：均退出 0。
2. `python3 -m py_compile parallel_execution_lib.py parallel-execution.py`：退出 0。
3. `git diff --check`：无空白错误。
4. `/bin/bash scripts/validate.sh`：退出 0；日志末尾为“校验通过”。

### 尚未覆盖的写入口

`parallel-cli.py start`、`parallel-desktop-register.py register` 及账本身份链仍由后续 T4–T6 分别收口。本任务不把由 `claim_lease` 产生的间接拒绝描述成这些入口已完成稳定契约；它们还需要各自的机器可读错误和不写入断言。

## 2026-09-05：T3 / Issue #146

- `parallel-worktree.py` 的 provision/reclaim 包装函数，以及 `parallel_worktree_lib.py` 的 `provision`/`reclaim` 均在路径规范化、manifest 读取、确认参数处理或 Git 调用前拒绝。
- provision/reclaim CLI 的 JSON 模式同样稳定返回 `PARALLEL_WRITES_DISABLED`；text 模式保留前缀化错误。`verify` 未更改，继续验证历史 worker 的只读状态。
- containment 回归用真实的旧 fixture worktree、分支与 manifest 做快照，并把库调用的 Git helper 设为失败桩：四个直接调用与两个 CLI 调用均拒绝，`--merged` 与 `--confirm` 不构成绕过，资源保持不变。

### 测试证据

1. `test-audit-safety-containment.sh`、`test-parallel-worktree-runtime.sh`、`test-parallel-readiness.sh`、`test-parallel-safety-gate.sh`、`test-parallel-guidance.sh`：均退出 0。
2. `python3 -m py_compile parallel-worktree.py parallel_worktree_lib.py` 与 `git diff --check`：均通过。
3. `/bin/bash scripts/validate.sh`：退出 0；日志末尾为“校验通过”。

### 尚未覆盖的写入口

真实 Agent 启动、Desktop 登记及其命令层仍在后续 T4–T8 范围内；本项不停止现有历史进程，也不删除旧 worktree。新自动并行执行器继续保持暂停。

## 2026-09-05：Checkpoint A / Issue #147

审阅结论：通过底层资源写入止血 checkpoint。run 创建、模块领取、lease、worktree provision 与 reclaim 都在其最早入口拒绝；反例中 ledger、历史 worktree、分支、脏文件与 manifest 均保持不变。这个结论只适用于 T1–T3，不等同于整个并行工作流已隔离或可发布。

### C1–C7 证据

1. C1–C5：containment、ledger、worktree、CLI、workflow integration 回归均退出 0。
2. C6：parallel-readiness、parallel-safety-gate、parallel-guidance 回归均退出 0，保留只读分析能力。
3. C7：`scripts/validate.sh`、phase guard（129/0）、verify artifacts（72/0）、Codex adapter（10/0）与 plugin smoke selftest 均通过。

### 审阅边界

没有运行真实付费 Agent、没有推送、发布、合并、删除分支或清理用户遗留资源。T4 起必须独立封闭 Agent 启动；在 T4–T8 与后续 checkpoint 完成前，不得将本模块称为“完整自动并行执行器”或建议生产使用旧写命令。

## 2026-09-05：T4–T6 与 Checkpoint B / Issues #148–#151

代码基线：`851508b`（包含 #148 `475a4fa`、#149 `739cad4`）。

- T4：start_worker/run_worker 和两个宿主 CLI start 请求均先拒绝。读取 manifest、发现可执行文件、启动进程的失败桩证明这些操作没有发生；历史进程状态由独立 fixture 写入，查询前后字节不变。
- T5：Desktop register 与内部构造入口均先拒绝。同目录、同宿主任务 ID、两个 run、两个模块和两种宿主的 8 个并发 CLI 请求全部失败，没有新增 lease/manifest。
- T6：修复文件名与内容 runId 错配时错误返回 available 的反例；关联 worker 的 module/run/base/ID 必须一致。账本 JSON 通过目录描述符和 O_NOFOLLOW 读取，拒绝文件/父目录符号链接；外部 canary 测试证明内容未被读取。查询错误返回非零，原记录保留。

Checkpoint B：通过。C1–C6 的 8 个脚本各自退出 0；C7 完整 validate 退出 0，phase 129/0、verify 72/0、Codex adapter 10/0、smoke selftest 退出 0。每个子进程均等待到实际退出码，未以“命令已启动”判通过。日志在本机 `/private/tmp/checkpoint-b-*.log` 和 `/private/tmp/spec-guard-checkpoint-b-validate.log`，可能随临时目录清理；本记录保留结果摘要。

剩余范围：T7 仍需修正 worker/process 只读语义和读取链；T8–T10 仍需收口用户命令及升级说明。底层写入口拒绝不意味着已加载的旧会话或旧进程停止，也不构成发布验收。

## 2026-09-05：T7–T11 最终验收 / Issues #152–#156

源码基线 `52fbf91` 加本次 T11 收尾差异，最终提交 SHA 由 Checkpoint C 记录。

### 结果与必要的连带修改

- T7 把旧 completed 显示为 unverified/recordedState；worker、run、lease、process 的身份和路径需互相匹配。host-owned 展示“完成与可回收性未核验”，不要求插件进程记录。缺失 worktree、错误身份、坏 JSON 与符号链接安全拒绝。查询时禁用 Git optional locks，完整目录快照没有变化。
- T8 让四个写命令只执行统一拒绝入口；移除了 merge/remove 等实际写流程与 stdin 双用途片段。回归直接执行文档 Shell，而不只检查关键词。
- T9 为现有 status CLI 增加 `--details`，由共享入口汇总两端诊断，子项失败传播为总体非零。Codex ops 和 Claude 命令在同一真实 Git fixture 中得到相同输出；已知受管 worker 不进入无绑定的 canonical next/deliver。
- T10 更新 README、Desktop 文档与 Unreleased 说明，明确源码尚未发布、旧会话不会自动停止、成果和账本保留。
- T11 将 9 套并行相关回归接入 validate；修正此前未接入门禁的 Desktop 登记旧断言。增加完整 Git/目录/用户文件快照、28 个并发重复写请求、JSON/text 拒绝、help/用法错误及独立 process 查询的缺失资源反例。

T7/T9/T11 的实际文件数高于最初估计，原因是必须同时更新共享 fixture、独立 CLI 退出码、next/deliver 文案和状态汇总消费者。未引入新的自动执行能力。最终审查另修复“独立 inspect 未检查 worktree 是否存在”及“worktree verify 的 JSON 失败仍输出文本”两个遗漏，并将资源核验移回上层查询，去掉账本库对 worktree 层的反向依赖。

### AC 与原审计映射

| 验收 | 证据 | 原问题及结论 |
|---|---|---|
| AC1 全部写入口先拒绝 | 11 个直接业务入口的移除保护变异均被拦截；所有 CLI 与 4 个命令 Shell 实际拒绝，28 个重复/并发请求保留脏文件和 Git 元数据 | F01/F03/F04：风险已隔离，执行器与汇合算法未实现 |
| AC2 保留资源、只读可信 | 目录/refs/ledger/文件字节快照、身份错配、文件及目录符号链接、外部 canary、缺失资源反例 | F09/F10：查询与身份缺陷已处置，不自动清理旧占用 |
| AC3 旧状态不误导 | completed→unverified+recordedState；started/unknown/坏记录非零；host 缺插件 process 正常返回未核验 | F01/F09：不再把进程退出或所有权当验收/回收凭证 |
| AC4 写命令解释与只读下一步 | 4 个真实 Shell 拒绝；只保留状态与只读分析指引 | F02/F03：危险流程已撤出，未提供替代自动汇合 |
| AC5 串行与未启用项目 | phase 129/0、verify 72/0、Codex adapter 10/0；readiness/safety/guidance 原套件通过 | 不声明 F05/F07/F08 已完成；完整任务绑定仍待下一模块 |
| AC6 回归进入门禁 | validate 执行 9 套并行回归；13/13 变异被拦截；两端实际状态片段输出一致 | F01–F04/F09/F10 的本模块处置有行为证据 |
| AC7 升级影响清楚 | README/Desktop/Unreleased 说明及文档回归通过 | 旧进程/旧版本会话仍需用户保存成果并确认停止或重启 |

### 最终执行记录

| 命令 | 结果 | 本机日志 |
|---|---|---|
| `/bin/bash scripts/validate.sh` | 退出 0，包含全部新增并行回归、Codex adapter 10/0 和 smoke selftest | `/private/tmp/spec-guard-containment-final-validate.log` |
| `/bin/bash plugins/spec-guard/hooks/test-audit-safety-containment.sh --selftest` | 退出 0；11 个保护删除 + 旧 completed + run 身份校验，共 13/13 被拦截 | `/private/tmp/spec-guard-containment-final-mutations.log` |
| `/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh` | 退出 0；129/0 | `/private/tmp/spec-guard-containment-final-phase.log` |
| `/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh` | 退出 0；72/0 | `/private/tmp/spec-guard-containment-final-artifacts.log` |
| `/bin/bash plugins/spec-guard/hooks/test-claude-desktop-mcp.sh` | 退出 0；7/0 | `/private/tmp/spec-guard-containment-final-desktop-mcp.log` |
| `git diff --check` | 退出 0 | 无空白错误 |

所有长运行均等待实际退出码后记录。变异只在独立临时副本进行，未改写原工作区。临时日志可能被清理，本报告保存可复跑命令与结果摘要。

### 五轴自查与未验证范围

按 code-review-and-quality 自查正确性、可读性、架构、安全和性能：已解决独立查询漏检与反向依赖；未新增依赖、后台进程或 hook 热路径，写入口采用单一异常政策，目录读取采用不跟随符号链接的方式。不支持这种安全读取的平台明确返回无法核验，未以不安全路径降级。

本记录是本地自查与行为回归，不是独立审查者批准，也不是四端原生 UI、Windows/远程环境、真实付费 Agent、发布安装或真实 GitHub/GitLab 完整 E2E 的证明。本模块不处理 F05–F08/F11 等其他审计模块，不重新开放自动执行器；未停止旧进程、未删除用户资源。

## 2026-09-05：Checkpoint C / Issue #157

审查源码提交：`93b903d`。C1–C7 及额外 Desktop MCPB 回归全部通过，13/13 隔离变异被拦截，AC1–AC7 证据已映射。已解决审查中的三项必改问题：独立 inspect 漏检资源、verify 的 JSON 错误响应不一致，以及账本库的反向层依赖。未发现本模块范围内仍阻塞交付的必改项。

结论：可以准备 `audit-safety-containment` 模块 PR，由人工评审最终决定合并。分支以 task commit 的 closing keyword 关联 #144–#157；这些 Issue 应在合入默认分支后关闭。没有将整个审计或自动并行执行器标记完成，没有在本 checkpoint 推送、合并、发布或清理分支。

后续仍按能力图依赖推进 tracker 正确性、历史语义/上游格式兼容及发布安装证据等审计模块；它们需要各自的 spec/plan 与验收。不能依据本模块通过就重新开放实验性并行写操作。
