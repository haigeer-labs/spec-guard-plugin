# Spec: audit-safety-containment

状态：SPEC APPROVED。用户在首模块 spec 评审请求后回复“继续”，据此进入计划阶段（2026-09-05）；实现计划及发布尚未批准。
所属能力图：[整体审计整改与收尾](CAPABILITY-MAP.md)。依赖：无。
覆盖：F01–F04、F09、F10 的隔离/诊断处置，不宣称完成自动执行器。

## Objective

让当前版本不再提供可误启动、误登记、误汇合或误回收的实验性并行写操作，同时让已有用户能够只读查看原资源和记录。普通串行功能与只读 readiness/safety/guidance 不因本模块而失效。

假设与取舍：用户已选择先收缩实验能力；本模块不修复真实 worker 调度和双模块自动汇合。现有活动进程不会因为更新插件自动停止；已加载旧版本的会话不受新代码保证，升级说明必须指出这一点。

## Tech Stack

- 现有 Python 3 标准库、Git、macOS `/bin/bash` 3.2 兼容 Shell。
- Claude Markdown commands、Codex ops skill 与现有只读脚本。
- 不新增包、数据库、后台服务或宿主私有 API。

## Commands

实施后必须运行的现有回归入口（从仓库根执行）：

```bash
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
/bin/bash plugins/spec-guard/hooks/test-parallel-execution-ledger.sh
/bin/bash plugins/spec-guard/hooks/test-parallel-worktree-runtime.sh
/bin/bash plugins/spec-guard/hooks/test-parallel-cli-execution.sh
/bin/bash plugins/spec-guard/hooks/test-parallel-workflow-integration.sh
```

新增验收入口（待实现，当前不存在）：

```bash
/bin/bash plugins/spec-guard/hooks/test-audit-safety-containment.sh
```

这些是实现验收命令，不代表本轮已经运行。真实宿主验收不是 smoke 自检，归跨模块发布验收另行记录。

## Interface Contract

### 1. 禁用范围

| 层 | 禁止的副作用入口 | 保留 |
|---|---|---|
| 用户命令/ops | parallel-execute、parallel-register-worker、parallel-integrate、parallel-reclaim 的写入行为 | 命令名可保留作为拒绝/解释入口，提供只读下一步 |
| execution CLI | create-run、claim-module | status |
| worktree CLI | provision、reclaim | verify |
| CLI worker | start | inspect |
| Desktop 登记 CLI | register | 通过既有状态入口诊断旧记录 |
| 可直接调用的业务函数 | create_run、claim_module、claim_lease、provision_worker/provision、start_worker/run_worker、register、reclaim_worker/reclaim | 纯计算、解析、验证函数 |

禁止新增 run/lease/manifest/process record、创建分支/worktree、启动 Agent、Git merge、自动删除或释放占用。不只删除 Markdown 代码块，还必须在底层业务副作用入口拒绝；不要把禁用规则塞入通用 JSON 写函数影响无关功能。

没有环境变量或隐藏 flag 可重新开启。既有 `--confirm`、`--merged` 等参数也不能绕过。帮助请求可正常返回；未知参数仍按用法错误处理。

对于语法正确的被禁用写请求，先拒绝再读取/创建目标资源，不为生成错误响应而初始化 ledger。JSON 输出为单个对象，退出 1：

```json
{"ok":false,"code":"PARALLEL_WRITES_DISABLED","message":"实验性并行写操作已暂停；已有成果保留，请使用只读状态检查。"}
```

文本模式同样明确拒绝并退出 1。底层业务函数抛出带相同稳定 code 的 LedgerError 子类；纯计算函数不必伪装为失败。code 可供程序判断，message 不应被调用者解析。

### 2. 只读状态与旧格式

- 不改写现有 v1 文件，不迁移 schema，不删除坏记录。原始文件仍是原始证据。
- 只读验证同时核对请求 ID、文件名、内容 runId、workerId、moduleId 及关联记录；不一致/缺失/不可读时返回 `ok=false`、`state=unknown` 和可理解原因，不猜测修正。
- 实际读取失败、身份冲突与无法核验必须非零退出；成功读取一个明确标为“不代表验收”的旧终态可以退出 0。退出 0 在文档中只表示本次查询成功。
- 原始 `completed` 记录对外展示为“旧版记录：进程退出成功，任务验收未核验”；若调整机器输出，将原值保留在 `recordedState`，有效 `state` 为 `unverified`，不继续给旧消费方传递可汇合的 completed 信号。新输出消费者与回归须同步更新。
- `owner=host` 只表示宿主管理，显示“完成与可回收性未核验”，不得显示“宿主可回收”。没有 process record 对 host-owned 不等同数据损坏；不自动套用插件自有 worker 的校验器。
- lease=claimed 仅表明旧记录存在；资源缺失或关联不一致显示待核验，不自动清除、重领或标记 reclaimed。
- 查询不得写回时间、修复记录、调用 gh/glab、创建目录、启动进程或进行 Git 写操作。错误输入含路径穿越或外部符号链接时不得读取任意外部文件；至少安全拒绝未知布局。

### 3. 对其他模块的边界

本模块输出“写操作暂停”和旧资源诊断契约，供后续 tracker 模块使用。不能为了封闭实验执行而禁用用户主动管理的所有 Git worktree，也不阻止无受管 worker 上下文的普通串行 next/deliver。

已有受管 worker 不应在提示中被送回不带绑定的 canonical next/deliver；此处给出暂停和人工核对说明。完整工作区任务绑定、普通两会话排重及 tracker 正确性由 audit-tracker-integrity 实现，不能提前宣称已覆盖 F07。

## Project Structure

主要改动归属（具体提交切片在计划阶段确定）：

- `plugins/spec-guard/hooks/parallel-execution.py`、`parallel-worktree.py`、`parallel-cli.py`、`parallel-desktop-register.py`：入口拒绝与诊断。
- `parallel_execution_lib.py`、`parallel_worktree_lib.py`、`parallel_cli_adapters.py`：上述 hooks 目录下的副作用边界与身份校验。
- `plugins/spec-guard/commands/parallel-*.md`、`plugins/spec-guard/skills/spec-guard-ops/SKILL.md`：入口说明和只读结果展示；只修改相关命令。
- 同目录现有 `test-parallel-*.sh` 与新增 containment 测试；`scripts/validate.sh` 接入新门禁。
- `README.md`、`docs/claude-desktop.md`、`CHANGELOG.md`：支持边界与升级影响；不重写历史审计或归档 spec。

## Code Style

保持现有显式校验和 LedgerError 风格，例如当前代码：

```python
def validate_run_id(value):
    if not isinstance(value, str) or not RUN_ID.match(value):
        raise LedgerError("runId 无效")
```

禁用政策只有一处定义，调用方不能各自维护 bool/环境开关。避免庞大通用执行框架；不新增外部依赖，不改变 phase hook 的只读及快速返回性质。

## Testing Strategy

1. 在临时 Git fixture 测试真实 CLI 与可导入业务函数；先证明旧实现会产生副作用/错误成功，再验证新实现拒绝。测试用桩记录调用，绝不启动真实付费 Agent。
2. 捕获调用前后的 refs、worktree 清单、ledger 文件集合/内容和用户文件内容，断言一致。不要只测返回码或关键词。
3. 顺序、并发、跨 run、重复调用、携带旧确认参数均被拒绝；拒绝前没有 git 写操作、Agent 调用或远端请求。
4. 准备旧 records：合法、缺失、损坏 JSON、filename/runId/workerId 不一致、host-owned、遗留 claimed、legacy completed；验证输出语义与只读性。
5. 执行保留命令的真实 Shell 代码路径；避免 stdin 同时作为 Python 脚本与 JSON 输入。机器错误不能被 `|| true` 吞掉后伪装整体通过。
6. 原测试中期望 provision/start/register/reclaim 成功的断言应按明确变更更新为禁用契约；旧格式读取 fixture 由测试专用构造提供，不保留生产绕过开关。
7. 常规串行、无 ledger 项目和只读并行分析继续通过原回归；测试夹具自身验证确实创建了待检查资源。

## Boundaries

- Always：所有拒绝先于业务副作用；保留原数据；区分记录状态与真实完成；新增正反行为测试。
- Ask first：扩展到自动停止旧进程、迁移/删除旧 ledger、修改 tracker、重新开放写入口或增加依赖。
- Never：自动 kill/archive/remove、清空 lease、把旧 completed 当验收通过、在 phase hook 加写入、为凑全绿删除失败测试。

## Success Criteria

| 编号 | 可验证结果 |
|---|---|
| AC1 | 全部列明的写入口，包括直接函数调用，在任何副作用前拒绝；重复/并发调用没有新增记录和资源 |
| AC2 | 旧资源文件与分支完整保留；只读查询不修改 ledger；坏身份安全拒绝 |
| AC3 | completed、claimed、host ownership 均不会被解释为已验收或可回收；错误可观察 |
| AC4 | 被禁用命令仍给出清晰原因与只读下一步，不含可直接执行的替代破坏性脚本 |
| AC5 | 普通串行与未启用项目无回归；只读候选分析不被全局关闭 |
| AC6 | 行为反例接入常规验证，新接口消费者与文档一致；不能只通过字符串断言 |
| AC7 | 升级说明明确：旧版本/已运行进程不被自动隔离，需保存成果并由用户确认停止或重启；不自动处理旧进程 |

本模块通过后，F01/F03/F04 等以“风险已缓解并验证”计，不以“完整功能修复”计；实际发布与安装覆盖由 audit-release-evidence 最终验收。

## Review Gate

以上禁用入口、旧状态输出变化与资源保留规则已进入 [批准计划](../tasks/audit-safety-containment/plan.md)。本模块 Issue #139，任务 #144–#157；落库不代表开发完成或已发布。
