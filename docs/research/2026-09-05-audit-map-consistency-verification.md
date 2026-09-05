# audit-map-consistency：阶段验收记录

日期：2026-09-05。状态：Checkpoint A 本地验证通过，供用户审阅；模块尚未交付。
基线：`44e3546017511cf563301841f15a11e992a28632`。
本阶段验证代码：`9e8d30a`（测试时内容与该提交一致）。
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
