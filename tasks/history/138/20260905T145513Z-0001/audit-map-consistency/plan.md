# Implementation Plan: audit-map-consistency

状态：PLAN APPROVED。用户在计划及 15 条 GitHub 子任务落库范围的确认请求后回复“继续”（2026-09-05）；15 条 task 及 14 条串行依赖已落库并回查，按序实施，未发布。
Spec：[audit-map-consistency](../../spec/audit-map-consistency.md)，2026-09-05 已获用户确认。
基线：`44e3546017511cf563301841f15a11e992a28632`；模块 #140；分支 `codex/fix/audit-map-consistency`。
依赖模块 #139 已合并且 14 个 task 全部关闭。未提交的自动执行器提案不纳入本模块。

## Overview

修复 F12 的并列顺序兼容与消费者分歧，修复 F05 的路径边界漏判。
每个切片先 RED 后 GREEN、运行相关回归、单独提交；不发布中间状态。
全过程保留第一模块的并行写入口封闭，不新增调度器或多 activeModule。

## Architecture Decisions

1. `capability_map.py` 为唯一图解析实现。严格解析结果增加声明组 `order_groups`；
   保留 `order` 为按组展开的稳定序列，保留表格行序 `rows`。验证依赖比较组位置，
   不比较组内展开位置；readiness 仍按 Depends on 计算依赖层。
2. 兼容摘要模式不进行严格构建顺序验证，保留旧 normalized_row、goal 和表格行序。
   `spec-digest.py compute` 的 `order` 不改含义；新严格入口不从该字段取得构建顺序。
   不改哈希算法、不引入 state schema 或自动迁移。
3. 增加薄 CLI `hooks/capability-map.py <map-path>`，输出单个 JSON：
   成功含 `ok`、`modules`（id/responsibility/dependsOn，表格行序）、`orderGroups`、`order`；
   图无效/不可读时 `ok:false`、`error`、非零退出。JSON 包装只序列化共享 parser，禁止第二份解析。
   图标题、评审是否通过、tracker 身份仍由同步入口处理，不把通用图解析器变成工作流控制器。
4. GitLab 和 Desktop 预览调用上述 CLI，使用参数数组或正确引用，不拼接执行任意 Shell。
   Python 缺失/输出坏 JSON/非零退出必须失败，不回退到旧正则解析。
   GitHub bridge 的显式创建前也加载严格结果；摘要仍来自 digest，依赖边仍来自 Depends on。
5. 路径先校验原始输入，再规范化为相对 POSIX 路径组件；禁止先归一化掉 `..` 掩盖越界。
   大小写/Unicode 规范化仅用于识别可能别名，不能擅自改写用户路径。
   physical 检查逐级使用不跟随链接的元数据读取，遇链接/不可信组件就停止，不读取外部目标。
6. `classify_group` 增加可选 project 上下文；保留旧单参数调用能力，但无上下文不能宣称物理检查通过。
   无 project 且无明确冲突时返回 needs-review；有项目、尚不存在的普通叶路径仍可做词法分析，
   报告说明物理隔离未被证明。直接库调用与文件入口共用字段/路径验证，不留绕过口。
7. 分类优先级：有已证明冲突则 sequential-required，同时保留其他不确定证据；
   否则有不确定项则 needs-review；只有声明完整且限定检查通过才 manual-parallel-eligible。
   空 paths 不代表有写边界证据；无法确定实际写范围的全空声明需人工补充，不能作为安全证明。
8. 不新建跨端执行适配层。Node MCP 是已有只读边界，调用 Python 不等于新增 Agent 控制。
   纯本地测试、MCP 协议测试与真实桌面验证分别记录，不借本模块宣称四端原生通过。

## Consumer Map

| 消费者 | 当前行为 | 计划接缝 |
| --- | --- | --- |
| readiness | 已调用共享 parser，按依赖层分组 | 接收并列组展开序列；保留 candidate-only 与基线提示 |
| safety / guidance | 经 readiness 读图 | 无重解析；保留错误和不确定原因到 text/JSON 输出 |
| GitLab sync-map | Shell 内联 Python 正则拆表格/箭头 | 共享严格 CLI；预览和 confirm 使用同一份解析结果 |
| Desktop GitHub preview | Node 正则拆表格，不验构建顺序 | 共享严格 CLI；按构建序列展示，保留只读和评审检查 |
| Desktop GitLab preview | 调用 GitLab 脚本且不传 confirm | 跟随该脚本改进，保持禁止写入 |
| GitHub bridge / sync-map / Codex ops | 模型按指引解析 | 指引要求先运行严格 CLI，再分别取摘要/依赖；不从 digest.order 猜顺序 |
| digest / phase / verify | 兼容 parser 与旧摘要 | 黄金样例保持稳定，真实漂移仍报告 |
| history readers | 旧快照可能缺 Build order | 保持兼容读取；运行相关历史回归，不修改历史真实性算法 |

## Verification Commands

命令均从仓库根运行；H 表示 `plugins/spec-guard/hooks/`，下文文件名未列目录时也在 H。

```bash
# C1：计划新增的聚焦回归与隔离变异自检；当前尚不存在
/bin/bash plugins/spec-guard/hooks/test-audit-map-consistency.sh
/bin/bash plugins/spec-guard/hooks/test-audit-map-consistency.sh --selftest
# C2：图与旧摘要
python3 plugins/spec-guard/hooks/spec-digest.py --selftest
/bin/bash plugins/spec-guard/hooks/test-parallel-readiness.sh
# C3：同步与协议预览（远端操作使用桩）
/bin/bash plugins/spec-guard/hooks/test-sync-map-gitlab.sh
/bin/bash plugins/spec-guard/hooks/test-claude-desktop-mcp.sh
# C4：边界与指引
/bin/bash plugins/spec-guard/hooks/test-parallel-safety-gate.sh
/bin/bash plugins/spec-guard/hooks/test-parallel-guidance.sh
# C5：项目交付门禁
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
# C6：历史兼容及写入口封闭回归
/bin/bash plugins/spec-guard/hooks/test-capability-history.sh
/bin/bash plugins/spec-guard/hooks/test-history-migration.sh
/bin/bash plugins/spec-guard/hooks/test-history-verification.sh
/bin/bash plugins/spec-guard/hooks/test-audit-safety-containment.sh
```

C1 随切片增量扩展，不提前提交针对未来未实现功能的失败断言。
所有 fixture 使用临时目录；变异仅发生在隔离副本，不能就地修改真实工作树。
`--selftest` 在 T11 实现；其他新增聚焦入口由 T1 引入。

## Implementation Slices

本节是技术拆分/验收设计，不是第二份任务状态清单。批准后每项 T 和 checkpoint 各落一条 GitHub task。
每项最多约 5 个文件、3 项验收条件；超出时先重新拆分，不把多处独立修改塞进同一提交。

### T1：共享解析器正确表达并列声明组

- 文件：`capability_map.py`、新增 `capability-map.py`、新增 `test-audit-map-consistency.sh`、`test-parallel-readiness.sh`（4）。
- 验收：线性/并列及反引号通过；重复、未知、漏项、空项、循环、同组依赖、逆序全部拒绝；库与 CLI 数据/退出码一致。
- 实施要点：新增 responsibility 结构字段时不改变旧 normalized_row；严格读取模块表不能误把无关表格当模块，歧义必须失败。
- 验证：C1、C2；重点反例是同组 `a,b` 且 b 依赖 a，不能被展开成“合法顺序”。
- 依赖：无。AC1。

### T2：锁定旧摘要与历史输入兼容

- 文件：`spec-digest.py`（仅必要兼容调整）、`test-audit-map-consistency.sh`、`test-phase-guard.sh`、`test-verify-artifacts.sh`（至多 4）。
- 验收：旧线性/无 Build order 样例得到基线固定摘要；仅修正声明格式不制造摘要漂移；真实职责/目标变化仍报漂移且不写 state/历史。
- 验证：C1、C2、C5 中 phase/verify、C6 的历史套件。黄金值取基线实际输出，不由新实现现场生成期望。
- 依赖：T1。AC3。

### T3：GitLab 同步统一使用严格图输入

- 文件：`sync-map-gitlab.sh`、`test-sync-map-gitlab.sh`、`test-audit-map-consistency.sh`（3）。
- 验收：预览按组展开顺序显示；坏图在任何远端 POST/本地 state 写入前失败；confirm 的桩调用消费同一解析结果且不制造组内依赖。
- 验证：C1、C3 的 GitLab 套件；桩记录明确零副作用/正确顺序，预览前后比较文件快照。
- 依赖：T1、T2。AC2；不修 F06 幂等/恢复，也不以此关闭 F06。

### Checkpoint A：图与摘要

T1–T3 后运行 C1（不含尚未实现的 selftest）、C2、C3、C5、C6。审阅坏图拒绝与旧摘要不变证据。
持久化结果到 `docs/research/2026-09-05-audit-map-consistency-verification.md`（计划新增）。未通过就停止。

### T4：Desktop 预览复用图验证

- 文件：`plugins/spec-guard/mcp/claude_desktop_server.mjs`、`test-claude-desktop-mcp.sh`、`test-audit-map-consistency.sh`（3）。
- 验收：GitHub 并列预览顺序正确、坏图 isError；缺 Python/坏 JSON/非零退出不能降级成功；两种 tracker 的预览无写入且不传 confirm。
- 验证：C1、C3，通过真实 stdio JSON-RPC 请求，而不是只查源码字符串；含带空格路径。
- 依赖：Checkpoint A。AC2、AC7。

### T5：GitHub 与 Codex 同步指引对齐严格输入

- 文件：`plugins/spec-guard/skills/spec-github-bridge/SKILL.md`、`plugins/spec-guard/commands/sync-map.md`、`plugins/spec-guard/skills/spec-guard-ops/SKILL.md`、`test-audit-map-consistency.sh`（4）。
- 验收：所有显式创建前先严格校验；digest.order 不被用作构建顺序；依赖取 Depends on，写入确认和增量记录约定保持不变。
- 验证：C1 实际执行新增前置片段/命令，坏图不得到达写桩；C5 的 validate 与 Codex adapter。
- 依赖：T4。AC2、AC7。片段回归不冒充模型真正遵循 skill 的宿主 E2E。

### T6：候选分析保留依赖层语义

- 文件：`parallel-readiness.py`、`test-parallel-readiness.sh`、`test-audit-map-consistency.sh`（3）。
- 验收：上游示例给出 billing/notifications 候选；线性列出但独立的模块仍可成为 candidate-only；没有最新远端证据时不宣称最新基线或可立即执行。
- 验证：C1、C2，在临时 Git 仓库用同图不同展示顺序对比结果；图无效明确非零。
- 依赖：T5。AC1、AC2、AC7。

### Checkpoint B：入口一致性

T4–T6 后运行 C1（不含 selftest）、C2–C6，比较共享样例在各真实入口的顺序和错误结果。
更新同一验收报告；不以一个入口通过替代其他入口，不以 GitLab 预览通过声称同步幂等修复。

### T7：词法边界与直接库输入验证

- 文件：`parallel_safety_gate.py`、`test-parallel-safety-gate.sh`、`test-audit-map-consistency.sh`（3）。
- 验收：尾斜杠/重复分隔符/点段/根路径的相等及包含正确，src 与 src-old 不冲突；非法输入和畸形字段不进 eligible；原始值与规范值可追溯。
- 验证：C1、C4；真实 parse_boundary 与直接 classify_group 各测，保留已知接口/迁移/全局配置冲突的正例。
- 依赖：Checkpoint B。AC4、AC5。

### T8：物理路径不确定性保守降级

- 文件：`parallel_safety_gate.py`、`test-parallel-safety-gate.sh`、`test-audit-map-consistency.sh`（3）。
- 验收：链接/失效链接/中间目录链接/权限不足/大小写及 Unicode 别名风险返回 needs-review；无项目上下文不可冒充物理验证；普通新路径仍可做限定声明分析，外部目标不被读取。
- 验证：C1、C4；临时真实文件系统 + 拦截越界读取的 canary；权限分支使用可控拒绝桩，不能靠当前账户碰巧读不到来判通过。
- 依赖：T7。AC5。允许项目根规范化，之后逐级检查；不扫描整个仓库，不跟随声明中的链接。

### T9：安全门及人工指引输出完整诊断

- 文件：`parallel-safety-gate.py`、`parallel-guidance.py`、`parallel_guidance.py`、`test-parallel-guidance.sh`、`test-audit-map-consistency.sh`（5）。
- 验收：text/JSON 都显示冲突及 needs-review 原因；非 eligible 不生成 worker 建议；图错误/读取失败非零且无误导性成功文案。
- 验证：C1、C4，执行两种 CLI 的 text/JSON；坏图和混合“冲突+不确定”结果均检查输出字段和退出码。
- 依赖：T8。AC4、AC5、AC7；不重新开放执行/登记/回收入口。

### Checkpoint C：边界可信度

T7–T9 后运行 C1（不含 selftest）、C2–C6；核对原 src/ 反例已拒绝、独立路径未误伤、外部内容未读、资源未改。
更新同一验收报告。仅报声明检查结果，不声称代码 diff、测试服务或运行时资源已经隔离。

### T10：用户文档明确修复范围

- 文件：`README.md`、`docs/claude-desktop.md`、`CHANGELOG.md`、`spec/parallel-readiness.md`、`spec/parallel-safety-gate.md`（5）。
- 验收：并列语法/顺序与摘要区别准确；保守路径检查及直接库无上下文限制明确；写入口暂停、未验证端和后续模块边界不被删掉。
- 验证：C5 validate；对照可执行例子与 C1/C3/C4 输出，旧 spec 保留历史背景并指出新契约，归档快照不修改。
- 依赖：Checkpoint C。AC7。

### T11：常规门禁与隔离变异验收

- 文件：`test-audit-map-consistency.sh`、`scripts/validate.sh`、本模块验收报告（3）。
- 验收：C1 常规回归接入 validate；`--selftest` 在隔离副本恢复旧行为时必红；AC1–AC7 均有命令、结果和残余限制。
- 验证：C1–C6 全部；变异覆盖不拆逗号、用展开位置放过同组依赖、恢复尾斜杠漏判、绕过库校验/链接检查、吞掉预览失败、改变旧摘要语义。
- 依赖：T10。AC6；需要任何等价变异例外时解释为何等价，不用豁免掩盖漏测。

### Checkpoint D：模块交付评审

T10–T11 后复查全部 AC 与项目 Definition of Done，运行 C1–C6、`git diff --check`，检查每个任务 closing commit。
报告区分已修复、仍受限与未验证；完成后才创建模块 PR（Closes #140），不自行合并/发布。
该 checkpoint 也落 task 并独立提交，不能用一行“全绿”代替证据。

## Task List

> Tasks tracked in GitHub Issues #140

- #159 T1: 共享解析器正确表达并列声明组
- #160 T2: 锁定旧摘要与历史输入兼容
- #161 T3: GitLab 同步统一使用严格图输入
- #162 Checkpoint A: 图与摘要
- #163 T4: Desktop 预览复用图验证
- #164 T5: GitHub 与 Codex 同步指引对齐严格输入
- #165 T6: 候选分析保留依赖层语义
- #166 Checkpoint B: 入口一致性
- #167 T7: 词法边界与直接库输入验证
- #168 T8: 物理路径不确定性保守降级
- #169 T9: 安全门及人工指引输出完整诊断
- #170 Checkpoint C: 边界可信度
- #171 T10: 用户文档明确修复范围
- #172 T11: 常规门禁与隔离变异验收
- #173 Checkpoint D: 模块交付评审

已按 T1、T2、T3、Checkpoint A、T4、T5、T6、Checkpoint B、
T7、T8、T9、Checkpoint C、T10、T11、Checkpoint D 的顺序创建 15 条 sub-issue，逐条回写编号至此。
每条通过原生 blocked-by 指向前一条，保守串行；不建立本地 checkbox 进度副本。
重跑先读此索引和远端，已建条目不得重复创建；阶段完成状态以 GitHub/分支 closing commits 为准。

## Risks and Mitigations

- 摘要兼容失守：在 T2 固定基线黄金值；保持兼容与严格模式用途分离，不重写历史和 state。
- 严格解析误吞无关表格/丢列：T1 用原样上游表格、现有文档及附加非模块表格验证；不扩大成通用 Markdown 引擎。
- 保守规则影响旧调用：T7/T8 明确无上下文/空声明降级，T10 给出原因与补充声明方式，不以放宽检查恢复假绿。
- POSIX/Windows 不一致：词法测试覆盖盘符/UNC；物理证据只覆盖实际测试系统，其余列为未验证，不宣称 Windows 全面支持。
- 跨进程输出失败：T4 验证可执行文件缺失/坏 JSON/错误退出；禁止旧正则兜底和成功空输出。
- 图校验通过掩盖 F06/F07：本模块不关闭 GitLab 幂等或任务绑定问题，远端真实流程留给后续模块。
- 测试污染真实仓库：fixture 与变异都隔离；任何外部写入调用使用桩，原始历史和未提交提案保留。

## Parallelization and Approval

本模块共享 parser、gate 和回归入口，全部串行，不启动子 Agent。只读检索/独立测试进程可以并发，不能同时改共享文件。
每个 checkpoint 审阅已落证据后继续；测试失败、规格外决定或高风险副作用必须暂停说明。

用户已确认本计划：新增薄只读解析 CLI、旧摘要语义不变、无项目上下文及全空边界保守降级。
确认同时授权为 #140 创建上述 15 条 GitHub task 及其依赖，并逐条回写索引；不包含业务仓库操作、自动执行、合并或发布。
task 落库完成后再按计划开始实现；本计划不是实现完成证明。
