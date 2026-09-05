# Implementation Plan: audit-safety-containment

状态：PLAN APPROVED。用户在计划与明确 GitHub 同步范围的确认请求后回复“继续”（2026-09-05）。已落库，按序实施；未发布。
Spec：[audit-safety-containment](../../spec/audit-safety-containment.md)。
范围依据：[整体整改](../../docs/research/2026-09-05-audit-remediation-scope.md)。
基线：`c2f247ce5b76fe87887206b0761ef8d16a17ea98`；已有未提交设计文档必须保留。

## Overview

先隔离实验性并行写入能力，再修正保留的只读诊断。原业务成果、旧记录、用户工作区不作自动清理。按入口纵向切片，每步同时包含行为回归；整个模块完成并评审前不单独发布中间版本。

本计划只处理第一模块。GitLab 同步、完整任务绑定、历史修正、Build order 和发布安装全面验收属于后续模块；不得借整改扩张成新执行器。

## Architecture Decisions

1. 在现有 `parallel_execution_lib.py` 定义唯一禁用异常/辅助函数，业务写入口在第一个资源操作前调用。纯计算、通用 JSON 写工具不受全局禁用影响。不引入新配置开关。
2. CLI 层负责既定 JSON/text 与退出码；业务函数抛出带 `PARALLEL_WRITES_DISABLED` code 的 LedgerError 子类。语法正确的禁用请求无需先找到仓库/记录或 CLI 安装。
3. 旧 v1 记录只读。只读输出区分 recordedState 与有效 state；原文件不迁移。身份链或路径不可信则失败，不猜测修复。
4. 测试专用 fixture 创建 Git 资源与旧 JSON；生产代码不导入 fixture。不通过重新启用被禁用函数来维持旧测试。
5. 所有切片串行，共用文件有依赖，不启动子 Agent。一个模块一个 PR，每个 tracker task 对应独立提交；中间切片不宣称所有入口都已封闭。

## Verification Commands

以下命令均从仓库根执行。C1 是待新增入口；其余现有入口需先核对基线结果。

```bash
# C1：新增本模块行为回归（实现后才能运行）
/bin/bash plugins/spec-guard/hooks/test-audit-safety-containment.sh
# C2：账本
/bin/bash plugins/spec-guard/hooks/test-parallel-execution-ledger.sh
# C3：worktree
/bin/bash plugins/spec-guard/hooks/test-parallel-worktree-runtime.sh
# C4：CLI
/bin/bash plugins/spec-guard/hooks/test-parallel-cli-execution.sh
# C5：命令流程
/bin/bash plugins/spec-guard/hooks/test-parallel-workflow-integration.sh
# C6：既有并行只读能力
/bin/bash plugins/spec-guard/hooks/test-parallel-readiness.sh
/bin/bash plugins/spec-guard/hooks/test-parallel-safety-gate.sh
/bin/bash plugins/spec-guard/hooks/test-parallel-guidance.sh
# C7：项目门禁
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
```

每个切片在隔离 fixture 中 RED→GREEN；先记录旧行为失败，再修复。失败不能降级为通过；不运行付费 Agent 或写远端来测试禁用路径。C7 全套在 checkpoint 和交付前运行，受影响的聚焦套件每步运行。

## Implementation Slices

这是计划的技术拆分与验收设计，不是另一份可勾选的任务清单。T 标识用于此计划内部依赖；批准后按一项一个 GitHub task 落库，进度以 Issue 为准。文件名未带目录的 Python/Shell 文件均在 `plugins/spec-guard/hooks/` 下。

### T1：让旧记录测试不依赖即将禁用的生产写入口

- 变更：新增测试专用 `test_parallel_fixture.py`；调整 `test-parallel-execution-ledger.sh`、`test-parallel-worktree-runtime.sh`、`test-parallel-cli-execution.sh` 的旧资源准备。
- 验收：fixture 自己验证真实 Git branch/worktree 及 JSON 内容；保留生产创建功能的旧行为断言直到相应切片改变契约；不引入生产 bypass。
- 验证：C2–C4 在当前生产实现上仍通过；故意破坏 fixture 的资源创建必须失败，不得测空对象。
- 依赖：无。预计 4 个文件。

### T2：封闭 run 创建与模块领取

- 变更：`parallel_execution_lib.py`、`parallel-execution.py`、`test-parallel-execution-ledger.sh`；新增 `test-audit-safety-containment.sh`。
- 验收：create_run、claim_module、claim_lease 与对应 CLI 在副作用前拒绝；JSON code/退出码符合 spec；纯计算和现有 status 仍可使用。
- 验证：C1、C2；语法正确但目标不存在的请求也稳定拒绝；重复/并发调用前后 refs、ledger 集合与内容一致。
- 依赖：T1。预计 4 个文件。

### T3：封闭 worktree 创建与回收

- 变更：`parallel-worktree.py`、`parallel_worktree_lib.py`、`test-parallel-worktree-runtime.sh`、`test-audit-safety-containment.sh`。
- 验收：provision/reclaim 及包装函数均拒绝；既有 confirm/merged 参数不能放行；旧 worktree、脏文件、分支及记录不变。
- 验证：C1、C3；Git 写命令桩零调用，直接函数与 CLI 均验证，verify 正向用例保留。
- 依赖：T2。预计 4 个文件。

### Checkpoint A：底层资源写入止血

T1–T3 后运行 C1–C7，核对反例日志和夹具有效性。其余入口尚未完成时不得宣称整体已隔离或发布。结果需审阅；失败停在本 checkpoint。

### T4：封闭真实 CLI 启动

- 变更：`parallel-cli.py`、`parallel_cli_adapters.py`、`test-parallel-cli-execution.sh`、`test-audit-safety-containment.sh`。
- 验收：start_worker、run_worker 与 start CLI 先拒绝，既不找可执行文件也不创建 process record；无 Codex/Claude 调用。
- 验证：C1、C4；两类 host、直接调用、缺 CLI、重复请求均无副作用；command_for 纯计算保留以解释旧记录。
- 依赖：T3。预计 4 个文件。

### T5：封闭 Desktop 登记

- 变更：`parallel-desktop-register.py`、`test-parallel-workflow-integration.sh`、`test-audit-safety-containment.sh`。
- 验收：register CLI 及业务函数拒绝，跨 run/同目录/同 host 并发请求不产生任何 lease/manifest；不调用 Desktop API。
- 验证：C1、C5；对旧双登记反例执行真实入口，断言成功登记数为零且原证据保留。
- 依赖：T4。预计 3 个文件。若登记断言另有归属，计划实施前先定位并只调整对应套件，不盲加豁免。

### T6：修正只读账本身份链

- 变更：`parallel_execution_lib.py`、`parallel-execution.py`、`test-parallel-execution-ledger.sh`、`test-audit-safety-containment.sh`。
- 验收：run 请求、文件名、内容及 worker 关联不一致显式 unknown/非零；损坏/缺失记录不自动修复；路径穿越/外部符号链接安全拒绝。
- 验证：C1、C2；好记录成功，坏记录失败；无 ledger 查询不创建目录；使用外部 canary 文件确认没有越界读取。
- 依赖：T5。预计 4 个文件。

### Checkpoint B：所有底层写入口禁用、记录可安全读取

T4–T6 后运行 C1–C7，并审查整个调用面是否仍能触达创建/启动/回收。异常 code、资源快照、并发反例均纳入证据。不把“所有 CLI 红了”误认为诊断正常。

### T7：修正 worker/process 只读语义

- 变更：`parallel_worktree_lib.py`、`parallel-cli.py`、`test-parallel-worktree-runtime.sh`、`test-parallel-cli-execution.sh`、`test-audit-safety-containment.sh`。
- 验收：旧 completed 输出 unverified + recordedState，保留原 JSON；started/缺失/身份不符可观察；host-owned 不套用 controller 验证。不能只凭 owner 或 claimed 判断可清理。
- 验证：C1、C3、C4；旧 completed、failed、started、unknown 及残留 lease 的正反例；查询前后文件字节一致。
- 依赖：T6。预计 5 个文件。

### T8：封闭用户写命令中的实际操作代码

- 变更：`commands/parallel-execute.md`、`commands/parallel-integrate.md`、`commands/parallel-reclaim.md`、`commands/parallel-register-worker.md`（均在插件目录下），以及 `test-parallel-workflow-integration.sh`。
- 验收：保留明确拒绝/只读下一步；不存在建议执行 merge/remove 或创建替代脚本的路径；废除原 stdin 双用途代码。
- 验证：C1、C5；执行保留的 Shell 入口片段，检查副作用调用记录；文档字符串检查只作补充，不能替代行为验证。
- 依赖：T7。预计 5 个文件。

### T9：贯通只读状态与 Codex 路由

- 变更：`commands/parallel-status.md`、`skills/spec-guard-ops/SKILL.md`（插件内）、`test-parallel-workflow-integration.sh`、`test-codex-adapter.sh`、`test-audit-safety-containment.sh`。
- 验收：宿主管理不显示“宿主可回收”；查询错误传到总体结果；Codex 路由不提供绕过；对受管 worker 不建议无绑定 canonical next/deliver，普通串行路由保留。
- 验证：C1、C5、C7 中 Codex adapter；实际状态片段无 `|| true` 假通过，host-owned 缺 controller process 不误报损坏。
- 依赖：T8。预计 5 个文件。

### T10：公开说明收缩与升级影响

- 变更：`README.md`、`docs/claude-desktop.md`、`CHANGELOG.md`、`test-parallel-workflow-integration.sh`。
- 验收：四端不承诺完整执行；旧会话不被新代码自动控制；保存成果与人工核对说明明确，不推荐直接删除旧 ledger 或回退到已知不安全版本。
- 验证：C5、C7；人工逐条对照 AC4/AC7 与命令实际行为；不修改历史审计结论。
- 依赖：T9。预计 4 个文件。

### T11：接入常规门禁并记录模块验收

- 变更：`scripts/validate.sh`、`test-audit-safety-containment.sh`，新增 `docs/research/2026-09-05-audit-safety-containment-verification.md`；本 plan 仅补真实 Issue 索引和证据链接。
- 验收：相关并行测试与新增 containment 回归接入门禁，已接入者不重复执行；测试失败不吞掉；报告逐条映射 AC1–AC7 和原审计 F 编号。
- 验证：C1–C7；在隔离副本中还原被封闭入口/破坏状态映射，确认新测试失败；记录源码 SHA、运行命令、退出码、日志和未验证项。
- 依赖：T10。预计 4 个文件。

### Checkpoint C：模块交付评审

完整回归、行为反例、差异检查及 AC 证据审阅通过后，才准备模块 PR。F01/F03/F04 的结论只能是已缓解，不是执行器已实现。此 checkpoint 不包含发布、自动合并或删除分支授权。

## Task List
> Tasks tracked in GitHub Issues #139；initiative #138。

- #144 T1：让旧记录测试不依赖即将禁用的生产写入口
- #145 T2：封闭 run 创建与模块领取
- #146 T3：封闭 worktree 创建与回收
- #147 Checkpoint: A 底层资源写入止血
- #148 T4：封闭真实 CLI 启动
- #149 T5：封闭 Desktop 登记
- #150 T6：修正只读账本身份链
- #151 Checkpoint: B 所有底层写入口禁用、记录可安全读取
- #152 T7：修正 worker/process 只读语义
- #153 T8：封闭用户写命令中的实际操作代码
- #154 T9：贯通只读状态与 Codex 路由
- #155 T10：公开说明收缩与升级影响
- #156 T11：接入常规门禁并记录模块验收
- #157 Checkpoint: C 模块交付评审

任务事实源：`github.com/yizhongkaimail-collab/spec-guard-plugin` 的 GitHub Issues。
已创建本轮 initiative #138、module #139–#143，以及首模块的 task/checkpoint #144–#157。创建后逐条回写编号；未关闭任何历史需求。

本次同步范围：1 个 initiative、5 个 module Issue；首模块 T1–T11 对应 11 个 task 和 A/B/C 三个 checkpoint task，按本计划顺序建立依赖。其余模块只落 module Issue，不预造未经 spec/plan 评审的 task。远端层级与全部串行依赖已只读核验一致。

每建成一个就记录编号并核验远端层级；此节最终仅保留有序 Issue 索引。实施进度不在本地另建 checklist 或 todo.md。

## Tracker Bootstrap Gate

同步前 `.agent/state.json` 缺失是旧 initiative 归档后的事实。本次获准同步后已创建新的映射，activeModule 为 audit-safety-containment；没有恢复旧归档映射。

补齐前：只读核对实际 GitHub 仓库身份（origin 使用 SSH alias，不能把 alias 当 API host）、登录、已有同目标 initiative 和模块；有歧义就暂停。以已注入 spec-digest 路径计算摘要，新建映射只用官方字段。已存在同一意图时复用/核对，不重复创建或覆盖其他需求。

新写入按 GitHub bridge 逐项持久化 Issue 与摘要。网络结果未知时先查询副作用再重试；不能自动恢复旧 archived state。该操作须获得用户明确确认，不因本计划文件存在而自动运行。

## Risks and Mitigations

| 风险 | 应对 |
|---|---|
| 改禁用函数使旧测试在 fixture 阶段失败 | T1 先分离准备逻辑，生产绕过开关禁止；每步保留正向读取测试 |
| 小步提交期间还有未封闭入口 | checkpoint 说明剩余范围；整模块评审前不发布或建议真实使用 |
| 旧消费者把退出 0/claimed 当完成 | 同步调整机器状态、文字和入口测试；坏身份非零，旧 completed 明确 unverified |
| 防护只写在 command，底层还能调用 | 对每个业务函数和 CLI 都做副作用快照断言 |
| 只读查询成为路径越界入口 | 验证规范化路径与记录链；不支持布局保守拒绝，不读外部 canary |
| 用户仍运行已加载旧版本 | 明确保存成果、确认停止/重启；本模块不越权 kill 或伪称立即隔离 |
| 计划超过单次切片能力 | 实际改动若超过约 5 文件或牵涉新契约，拆分并说明，不能扩大本模块范围 |

## Approval and Completion

本计划与明确的 GitHub 同步范围已获确认；远端映射已建立。实现、测试结果以各 Issue 和后续验收报告为准，不因落库而判定完成。新自动并行执行器仍暂停，合并/发布另行评审。
