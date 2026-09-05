# audit-map-consistency：阶段验收记录

日期：2026-09-05。状态：Checkpoint A、B、C 本地验证通过，当前 C 供用户审阅；模块尚未交付。
基线：`44e3546017511cf563301841f15a11e992a28632`。
Checkpoint A 验证代码：`9e8d30a`（测试时内容与该提交一致）；B 证据见文末。
规格：[audit-map-consistency](../../spec/audit-map-consistency.md)。
计划：[implementation plan](../../tasks/audit-map-consistency/plan.md)。

## Tracker 与交付范围

模块 #140 下创建并回查了 task #159–#173，共 15 条、14 条串行 blocked-by 边。
任务编号每建成一条立即回写计划，未创建 todo.md。

本地提交：

- `bfa29db`：已批准的规格、计划和 tracker 索引。
- `db8e7d2` / #159：共享严格解析器支持并列声明组，并增加只读 JSON CLI。
- `d8bf66e` / #160：旧摘要黄金值与真实漂移回归，不改摘要算法。
- `9e8d30a` / #161：GitLab 预览/确认接入共享严格图解析。
- #162：本检查点的验收记录提交。

GitHub task 的关闭依赖将来模块 PR 合入默认分支；本分支的 closing commit 是尚未合并阶段的完成证据。
此次没有推送、创建模块 PR、合并、发版或更新已安装插件。

## RED → GREEN 证据

### T1 / #159

新增 `test-audit-map-consistency.sh`，首跑退出 1：上游并列顺序和带反引号的并列顺序被拒绝；
无关表格里的 Risk 被当成模块；新 CLI 尚不存在。实现声明组后，测试进一步发现末尾空依赖未被拒绝。
补齐严格表格读取后，又用紧凑空依赖行 `|identity|Accounts||` 得到 RED，再修复边框剥离。

最终 9 组聚焦测试通过，覆盖多组正反输入：

- 并列/线性、两种箭头、反引号、空根依赖。
- 空组/空元素、重复/未知/漏项、同组依赖、自依赖、循环、逆序、非法 module id。
- 缺表头分隔行、列缺失、多个模块表或多个声明顺序的拒绝。
- 无关表格与 fenced 示例不参与严格图解析。
- CLI 的 JSON/退出码、带空格文件路径、文件缺失、原文件保持不变。

声明组与依赖层分开；依赖验证比较组位置，不能靠展开组内顺序放过依赖。
严格表格读取与兼容摘要读取有意分开：不为修正图输入而重算旧快照。

### T2 / #160

用 `git show 44e3546:...` 取得当时的 parser 与 digest，在内存执行基线实现生成固定期望。
黄金值：second=`d6b94af161e6`，first=`499ae133d946`，目标=`23acd1f8517a`。
被测代码不重新生成这些期望；样例全文保存在回归中。

3 组新增兼容测试通过，聚焦总数变为 12：旧图缺少 Build order 可读、摘要 order 仍为表格行序、
严格 order 为构建序列、CRLF/尾空白兼容；真正修改职责/目标/依赖仍报告漂移，map/state 字节未被改写。
这是兼容性特征测试，本阶段没有修改生产 digest；其旧行为本来就应通过，不能声称它曾存在本次修复的 RED。
针对摘要算法的隔离变异验证留到 #172，不把普通通过当作变异测试已通过。

### T3 / #161

真实运行 GitLab Shell 入口，外部 API 用临时 glab 可执行桩替代。3 条测试在旧脚本上全部失败：

- 合法并列图无法预览。
- 声明组展开顺序无法用于确认同步。
- 含循环/逆序依赖的图竟执行了 5 次测试 Issue 创建并写入 fixture state。

改为先调用共享严格 CLI 后，3 条全部通过，聚焦总数变为 15。
预览不调用 POST，项目文件快照不变；坏图在 POST 和 state 写入前失败；
确认路径创建恰好 1 个 initiative + 4 个模块，按声明顺序而非表格行序，未产生额外关系写入。
测试包括带空格的项目路径。所有 GitLab 创建都是桩调用，没有访问或写入真实 GitLab 项目。

## Checkpoint A 验证结果

完整命令组见计划 C1–C6；本轮均从仓库根执行并核对实际退出码。

| 验证项 | 结果 |
| --- | --- |
| test-audit-map-consistency.sh | 15 组通过，退出 0 |
| spec-digest.py --selftest | 通过，退出 0 |
| test-parallel-readiness.sh | 通过，退出 0 |
| test-sync-map-gitlab.sh | 通过，退出 0 |
| test-claude-desktop-mcp.sh | 7 / 0，退出 0；协议/桩测试，不是原生 UI 验收 |
| test-parallel-safety-gate.sh、test-parallel-guidance.sh | 既有回归通过，退出 0；不表示 F05 已修复 |
| scripts/validate.sh | 完整通过，退出 0 |
| test-phase-guard.sh | 129 / 0，退出 0 |
| test-verify-artifacts.sh | 72 / 0，退出 0 |
| test-codex-adapter.sh | 10 / 0，退出 0 |
| codex-plugin-smoke.sh --selftest | 退出 0；内部故意失败/未就绪样例属于判决器自检 |
| test-capability-history.sh | 11 / 0，退出 0 |
| test-history-migration.sh、test-history-verification.sh | 均退出 0 |
| test-audit-safety-containment.sh | 通过，退出 0；暂停写入口仍有效 |
| git diff --check | 通过 |

本模块的 `--selftest` 尚未实现，常规 validate 尚未接入本模块新套件（#172）；本轮 C1 是显式运行。
不得把这两项写成已验收。现有 validate 内的其他并行回归保持启用。

宿主临时日志：`/private/tmp/spec-guard-map-checkpoint-a-{validate,phase,artifacts}.log`。
`/private/tmp/spec-guard-map-checkpoint-a-focused.log` 只保存组合命令末尾的 containment 输出；
前面各聚焦命令的结果在工具执行记录中，不能声称此文件包含全部聚焦日志。
上述日志是本机临时辅助证据；持久化摘要、测试源码和提交才随仓库保存。

## 环境故障与处理

T1 首轮 validate 退出 1，原因是既有 `test-checkers.sh` 临时给 spec-digest.py 加注释后，
Git 还原操作无法在沙箱内创建 `.git/index.lock`。保留失败日志后，仅用补丁移除自测新增注释，
确认 spec-digest.py 与 HEAD 完全一致，再以所需权限运行 validate，退出 0。
Checkpoint A 使用同样的所需权限完整通过。没有删测试、跳过失败项或用 no-verify 掩盖错误。
该自测目前仍有就地暂改行为，后续运行需注意权限和清理结果；未借本任务重构测试基础设施。

## 阶段自查与剩余风险

依据 code-review-and-quality 的五轴进行本阶段自查，非独立 Agent/多人评审：

- 正确性：先看 RED/GREEN 和输入/输出；空依赖与末尾空项的两种成因分别处理，未放宽同组依赖。
- 可读性：声明组显式建模，薄 CLI 只序列化/报错；已删除 GitLab 的重复拆表格/箭头逻辑。
- 架构：同步入口仍负责 tracker/标题/评审与远端操作；共享 parser 不承担任务调度，digest 算法仍唯一。
- 安全：项目路径与 JSON 参数被引用，不将模块内容拼成可执行命令；坏图先于写入拒绝。
  未验证跨进程读取期间图被其他会话修改的竞态；同步完整恢复及任务绑定仍归 #141。
- 性能：新增 Python 调用位于显式同步操作，不增加每轮 phase hook 的网络调用；未新增包或后台服务。

AC1 已有本阶段证据；AC3 的黄金值/漂移证据已落地；AC2 仅完成共享解析与 GitLab 接缝。
Desktop GitHub 预览、GitHub/Codex 指引仍待 #163–#165；F05 路径安全门待 #167–#169；
文档/常规门禁/变异与最终验收仍待后续任务。F05、F12 均不能在此时整体关闭。

下一阶段是 Checkpoint B 对应的入口统一。按计划在 A 提交记录后交用户审阅，不越过检查点自行宣称模块已完成。
自动执行器持续暂停；未进行四端原生、真实 GitLab 业务流程、发布包或安装版本验收。

## Checkpoint B：入口一致性（2026-09-05 续）

以下是用户确认 A 后新增的阶段记录；上面的 A 结论保留为历史，不代表 B 的当前进度。
验证代码：`f257ab9`，本阶段三个切片均独立提交，报告提交对应 #166：

- `24b2d24` / #163：Desktop 预览复用共享严格解析器。
- `de5802b` / #164：GitHub bridge、sync-map 命令与 Codex ops 的创建前校验对齐。
- `f257ab9` / #165：明确候选不等于可执行，并锁定依赖层语义。

### T4–T6 的行为证据

T4：新增 4 组真实 stdio JSON-RPC 测试，带空格项目目录下执行 MCP 服务。
修复前的失败与修复后 19 组通过已记录于 #163 closing commit；本检查点重跑全部通过。
GitHub 预览按声明顺序展示，不再按表格行序；坏图、Python 缺失、非零退出、坏 JSON、
缺字段/空模块/重复模块/未知顺序/坏行均返回 isError，不回退旧正则。
非零退出反例使用结构合法的 JSON，避免误把输出形态错误当成退出码检查证据。
GitLab 预览仍不带 confirm；两类预览前后比较完整项目文件快照，未发生写入。

T5：首跑退出 1，原因是 bridge 尚未提供可执行严格校验片段。添加指引后聚焦 20 组通过。
测试从三个实际文档中提取 bash 前置片段并执行，在其后接测试 gh 写桩：合法图可到达写桩，
坏图和当前安装包缺少解析器时非零退出，写桩未执行。
旧摘要仅刷新路径保持原约定；新建/补充使用严格 order，摘要 compute.order 仍是表格行序。
依赖边仅取 Depends on，不从组内顺序推导；未更改写入确认、增量记账或旧摘要算法。
两份修改后的 skill 均通过 skill-creator quick_validate；Codex adapter 与完整 validate 通过。
这证明片段本身能阻断后续命令，**不是**模型必定遵循 skill 的原生宿主 E2E 证明。

T6：在真实临时 Git 仓库配置 origin/trunk 跟踪 ref，运行同图三种 Build order 的真实 CLI：
并列、线性、调换 billing/notifications 展示顺序。结果均为 layer 1 的同一对 candidate-only，
只改变展示顺序，不改变依赖关系。无刷新时 fresh=false，保留远端新鲜度警告；坏图非零且无成功输出。
运行前后比较 refs、索引、state 和图等项目文件，默认只读分析没有改写。

首轮测试自身曾将线性图的预期展示顺序写反，已修正为逐例显式期望；该失败不计作产品缺陷。
修正测试后唯一 RED 是缺少 notice。最小修复在 JSON 与文本输出增加说明：
“候选仅来自 Depends on 依赖层；未核验任务状态或运行资源，不表示可立即领取或执行。”
新增 3 组后共 23 组通过。既有本地 bare remote 刷新测试也核对该说明：
即使 fresh=true、无新鲜度警告，仍然只是 candidate-only，不是领取/执行授权。
依赖层算法本来已有上述语义，本次没有重写算法，更没有增加自动调度。

### B 验证结果

C1/C2 使用 T6 GREEN 的同内容结果；其后生产代码未变化，不重复运行制造额外次数。
C3–C6 在 B 阶段运行，各组合命令用 `&&` 串接且均核对实际退出 0。

| 验证项 | 结果 |
| --- | --- |
| C1 test-audit-map-consistency.sh | 23 组通过，退出 0 |
| C2 digest selftest、parallel-readiness | 均退出 0 |
| C3 sync-map-gitlab、claude-desktop-mcp | 均退出 0；MCP 7 / 0 |
| C4 parallel-safety-gate、parallel-guidance | 均退出 0；既有路径回归，不代表 F05 修复 |
| C5 scripts/validate.sh | 完整通过，退出 0；自测后 spec-digest.py 与 HEAD 一致 |
| C5 phase-guard、verify-artifacts | 129 / 0、72 / 0，组合退出 0 |
| C5 Codex adapter、smoke selftest | 10 / 0、判决器自检退出 0，非原生宿主验收 |
| C6 capability-history、history-migration、history-verification | 11 / 0；其余两套均退出 0 |
| C6 audit-safety-containment | 通过，退出 0；写入口仍封闭 |
| git diff --check | 通过 |

临时日志：`/private/tmp/spec-guard-map-t6-{red,red-corrected,green}.log`、
`/private/tmp/spec-guard-map-checkpoint-b-{validate,focused,hooks}.log`。
此次 focused 日志保存整个组合命令的输出；部分历史脚本成功时没有汇总文本，以组合退出码确认。
本模块 `--selftest` 与接入常规 validate 仍留到 #172，尚未实现。

### B 自查与边界

按 code-review-and-quality 五轴做本阶段自查，按批准计划串行执行，非独立 Agent 评审：

- 正确性：各入口共同消费严格图；Node 只验证跨进程形态，没有第二套依赖解析。
  缺运行环境或坏输出显式失败；旧摘要刷新与新建输入验证分开。
- 可读性：已删除 Desktop 的表格正则路径；readiness 只新增一条统一说明，不引入额外状态机。
- 架构：保留依赖层与声明组区别，不改变 digest.order、单 activeModule 或上游流程。
- 安全：MCP 使用参数数组，片段正确引用路径；测试外部写入全为桩。
  仍未解决其他会话在校验后修改图的竞态，不能把本阶段当作跨会话事务/锁实现。
- 性能：预览新增一次 Python 子进程，不新增依赖、后台服务或每轮 hook 网络请求。
  未做大图性能基准，不宣称延迟上限。

AC2 的入口一致性已有本地证据，F12 仍需最终文档/常规门禁/隔离变异验收后整体收尾。
F05 的词法/物理路径风险还未修复；GitLab 幂等恢复与任务绑定问题仍归后续模块。
未测试四端原生完整交互、真实 GitHub/GitLab 业务流程或已安装包；未推送、合并、发版、更新插件。
自动执行器提案未改动。本分支截至 B 完成 #159–#166 的 8 个任务/检查点，尚余 7 项。
下一步为用户审阅 B 后执行 #167–#169 的路径边界修复及 Checkpoint C，不提前开放自动并行。

## Checkpoint C：边界可信度（2026-09-05 续）

用户确认 B 后按序实施。本段更新当前进度，不抹去 A/B 的历史结论。
验证代码：`a03c76e`；本阶段提交：

- `9df61cd` / #167：词法组件比较、公共字段校验与原始/规范路径证据。
- `fd45733` / #168：不跟随链接的物理路径检查与保守降级。
- `a03c76e` / #169：安全门和人工指引完整保留诊断。
- #170：本检查点的报告提交。

### T7–T9 的 RED → GREEN

T7 首跑退出 1（47 个子例失败、3 个错误）；旧实现漏判 `src/`、点段、重复分隔符和根路径，
直接库调用可绕过字段验证，部分畸形值使分类函数崩溃。
文件入口与库入口改用同一字段/路径验证；先校验原始路径，再按组件规范化和比较。
空值、父目录穿越、绝对路径、盘符/UNC、反斜杠、通配符、控制字符和歧义首尾空白被拒绝。
合法 raw 值保留，normalized 用于比较；`.` 覆盖全仓库，`src` 与 `src-old` 不误判包含。
空 paths 不再作为充分边界证据；已证明的接口/迁移/全局配置/测试资源冲突优先返回
sequential-required，同时保留其他模块的无效声明原因。修复后 27 组与 C4 通过。

T8 新测试初次因导入位置错误未跑起来；调整到 hooks 路径注册之后，该次不计产品 RED。
有效 RED 退出 1（2 个失败、7 个错误）：缺少 project 参数/物理检查，无上下文仍给 eligible。
新增 5 组后共 32 组通过，覆盖已有普通文件、未创建路径、内部/外部链接、叶链接、
中间目录链接、失效链接、非目录组件、可控权限拒绝、大小写与 Unicode 别名风险。

物理检查在允许规范化的项目根下，逐级使用目录 fd、no-follow 元数据与目录打开操作；
不跟随声明中的链接。canary 测试拦截 stat/open 与内容读取，且要求元数据拦截器实际被调用，
四类链接均返回 needs-review，没有访问外部 canary，外部内容保持不变。
权限分支由可控 PermissionError 桩验证，不依赖当前账号是否真的读不到文件。
无项目上下文返回 needs-review；普通未来路径可以完成限定声明比较，但标记 not-created，
并显示“不证明物理隔离”。现有单参数调用仍可用，只是不能继续给无物理证据的绿灯。

T9 首跑退出 1（5 个失败、3 个错误）：guidance 丢失路径诊断，文本缺少原因，
边界解析的具体错误被吞掉，坏图/坏编码在 CLI 暴露 traceback。
修复后 35 组与 C4 通过。两种 CLI 的 text/JSON 均保留模块、分类、原始/规范路径、
物理检查结果、冲突及不确定原因，并显示基线新鲜度与候选非执行授权的说明。
混合“已证明冲突 + 别名不确定”保留两类证据，仍判 sequential-required；非 eligible 的
worker 建议始终为空。坏图、图缺失与图编码错误非零退出，无成功输出或 traceback。
单个模块边界缺失/无效属于可报告的 needs-review，不冒充可执行，也不使整张报告丢失其他证据。

为保留源头错误并共用文本诊断，T9 实际修改公共 gate 库，替代原计划可选的
test-parallel-guidance.sh 改动；实际仍为 5 个文件。新增 CLI 行为回归集中在 C1，
既有 guidance 回归照常执行。没有另建解析器或输出框架。

### C 验证结果

C1/C4 使用 T9 GREEN 同内容结果；其后无生产改动。其余命令组在 C 阶段执行并核对实际退出码。

| 验证项 | 结果 |
| --- | --- |
| C1 聚焦回归 | 35 组通过，退出 0 |
| C2 digest selftest、readiness | 通过，退出 0 |
| C3 GitLab sync、Desktop MCP | 通过，退出 0；MCP 7 / 0 |
| C4 safety gate、guidance | 通过，退出 0 |
| C5 完整 validate | 通过，退出 0；自测后 spec-digest.py 与 HEAD 一致 |
| C5 phase、verify-artifacts | 129 / 0、72 / 0，组合退出 0 |
| C5 Codex adapter、smoke selftest | 10 / 0、判决器自检退出 0 |
| C6 三套历史回归、写入口封闭回归 | 均退出 0；capability-history 11 / 0 |
| git diff --check | 通过 |

临时日志：`/private/tmp/spec-guard-map-t7-{red,green}.log`、
`/private/tmp/spec-guard-map-t8-{red,red-corrected,green}.log`、
`/private/tmp/spec-guard-map-t9-{red,green}.log`、
`/private/tmp/spec-guard-map-checkpoint-c-{validate,focused,hooks}.log`。
C1 的 --selftest 与接入常规 validate 尚待 #172，不计为已通过。

### C 自查与残余限制

按 code-review-and-quality 与 security-and-hardening 做本地自查，非独立 Agent 审查：

- 正确性：正反路径、两种输入入口、三种分类及混合证据都有行为断言；没有用异常降级掩盖已知冲突。
- 可读性/架构：共享字段验证、组件比较、物理检查和文本输出分别位于小函数；不新增依赖或状态 schema。
- 安全：外部声明仍是不可信数据，元数据检查不读取声明目标内容；规范化不消除原始穿越证据。
  本阶段的 CLI 测试比较完整临时项目文件快照，未改 state、refs、索引或图；未运行任何 Agent/worktree 写操作。
- 性能：只枚举声明路径的祖先目录，不递归扫描仓库；尚未做超大目录/边界数量的性能基准。

限定检查不是隔离证明：不递归检查目录后代，不检测所有硬链接/挂载别名，
不保证检查后文件系统不变化，不审核实际代码 diff、测试服务、端口或运行资源。
平台缺少 no-follow 支持时降级；本地证据来自当前 macOS，未作 Windows 或四端原生验收。
未在真实 GitHub/GitLab 业务仓库执行新流程，未推送、合并、发布或更新安装包。

AC4/AC5 已有本地修复证据，F05/F12 整体关闭仍需 #171–#173 的文档、常规门禁、
隔离变异和最终交付检查。当前完成 12/15 个任务/检查点，剩余 3 项。
自动执行器保持暂停；未提交提案保持原样。C 提交后交用户审阅，再进入最终收尾阶段。

## Checkpoint D：模块交付评审（2026-09-05 续）

T10、T11 和本检查点在 C 后完成。T10 的用户文档提交为 `167ea36` / #171；
T11 的常规门禁与隔离变异提交为 `ca5eb75` / #172；本段报告提交对应 #173。

### 完整验收与任务可追溯性

在代码未再变更的条件下，重新串行运行 C1–C6。结果：

| 验证项 | 结果 |
| --- | --- |
| C1 `test-audit-map-consistency.sh` | 35 组通过，退出 0 |
| C1 `--selftest` | 7 个隔离变异全部被抓到，退出 0 |
| C2 digest selftest、readiness | 均退出 0 |
| C3 GitLab sync、Desktop MCP | 均退出 0；MCP 7 / 0 |
| C4 safety gate、guidance | 均退出 0 |
| C5 `scripts/validate.sh` | 完整通过，退出 0；checkers 34 / 0 |
| C5 phase、verify-artifacts、Codex adapter | 129 / 0、72 / 0、10 / 0 |
| C5 Codex smoke selftest | 判决器自检退出 0；故意的“hook 输出无事实”反例不是宿主成功 |
| C6 capability-history、history-migration、history-verification | 均退出 0；capability-history 11 / 0 |
| C6 audit-safety-containment | 通过，退出 0；实验写入口仍封闭 |
| `git diff --check` | 通过 |

`--selftest` 在临时复制的 `plugins/spec-guard/` 内逐项恢复旧行为，随后运行同一份聚焦回归；
真实工作区不写入变异。被抓到的方向为：不拆并列 Build order、用展开位置放过同组依赖、
尾斜杠不规范化、库入口绕过字段验证、链接检查绕过、Desktop 吞掉子进程失败、摘要只 hash id。
此前 `--selftest` 参数只是被忽略、普通测试返回 0；本轮已修正并接入常规 `validate.sh`。

本分支从基线 `44e3546` 至本检查点，#159–#173 各有一条 closing commit：
`db8e7d2`、`d8bf66e`、`9e8d30a`、`7898611`、`24b2d24`、`de5802b`、`f257ab9`、
`68cc548`、`9df61cd`、`fd45733`、`a03c76e`、`d8dd546`、`167ea36`、`ca5eb75` 与本提交。
这些 GitHub Issue 在模块 PR 合入默认分支前仍应保持 open；不创建本地 checklist 代替 tracker。

### AC 与 Definition of Done 复查

- AC1：严格共享解析接受线性/并列顺序、拒绝坏图；readiness 依赖层不混用 Build order。
- AC2：GitLab、Desktop、GitHub/Codex 指引均有共享入口/片段回归；没有新增远端写入或第二解析器。
- AC3：基线黄金 digest、旧无 Build order 输入与真实漂移均有回归，算法仍只有 `spec-digest.py` 一份。
- AC4/AC5：词法等价、父子关系、非法输入、空声明、别名、链接与无 project 上下文均保守处理；
  canary 证明未读取外部链接目标。
- AC6：聚焦回归已进 validate，7 条隔离变异均被杀死；没有在真实工作区做就地变异。
- AC7：README、Desktop 文档、两份行为 spec、CHANGELOG 和验收报告均区分候选、声明检查、
  运行时安全、四端原生验证和写入口暂停。

按 Definition of Done 与五维代码审查做了本地复核，未发现阻断合入的问题：
输入在路径、CLI JSON 与跨进程边界上显式验证；没有新依赖、后台服务、状态 schema 或自动执行分支；
共享 parser/digest 没有复制；每个行为变化都有 RED/Green 或隔离变异证据。变更按任务提交，
文档与公开命令契约同步。此为作者自审，**尚不替代合并前的人类 PR 审查**。

### 已修复、仍受限与未验证

已修复：F12 的并列 Build order 消费者分歧，以及 F05 的已知路径拼写、直接库输入、
链接/别名不确定性和诊断缺失。修复均是保守拒绝或降级，不扩张自动化权限。

仍受限：该检查不递归验证目录所有后代，不检测所有硬链接/挂载别名，不防检查后的文件系统变化，
也不证明实际 diff、端口、测试服务或运行资源隔离。GitLab 同步幂等/恢复与任务绑定仍在后续模块范围内。

未验证：真实 GitHub/GitLab 业务仓库上的本模块端到端写流程、四端原生 UI、Windows 行为、
大目录性能、已安装包升级和发布。Desktop 的 MCP 协议测试不等于 Desktop UI E2E；Codex smoke
自检不等于已加载本分支插件的宿主通过。

自动执行器、worktree 创建、Agent 启动、登记、汇合与回收仍保持暂停。本模块未推送、合并、发布、
安装或删除任何资源；CheckPoint D 后才可按用户批准创建模块 PR，PR 合入前不称 Issue 已关闭。
