# audit-safety-containment 增量验证记录

状态：PARTIAL。不是整个模块通过，不代表实验写入口已禁用。

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
