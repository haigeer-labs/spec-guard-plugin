# Spec: audit-map-consistency

状态：SPEC APPROVED。用户在规格评审请求后回复“继续”（2026-09-05）；实施计划随后获确认，GitHub task #159–#173 已落库，按计划实施。
所属能力图：[整体审计整改与收尾](CAPABILITY-MAP.md)。模块 Issue：#140。
依赖：audit-safety-containment（#139 / PR #158 已合并，14 个 task 已关闭）。
覆盖：F05、F12；其他审计问题只做回归，不借本模块扩大范围。

## Objective

让同一份合法能力图在解析、同步预览、摘要检测和并行候选分析中含义一致，
让显式边界检查不再因路径拼写差异漏报冲突。用户能够读懂候选来源、冲突原因
及未能验证的边界，而不会将“图上可并列”误解成“插件已经可以自动执行”。

假设与取舍：

- 沿用已批准的五模块整改范围；本轮仍串行推进，不修改单 activeModule 契约。
- 并列 Build order 是输入格式，不是 Agent 调度指令；第一模块的写入口封闭持续有效。
- 优先维护现有摘要兼容性，不为统一解析而静默重算历史或覆盖用户映射。
- 不追求任意自然语言或任意 Markdown 方言；未支持/含糊输入给明确诊断。

## Baseline Evidence

基线：合并提交 `44e3546017511cf563301841f15a11e992a28632`，2026-09-05。

- 使用真实 `capability_map.parse_map`、以内存文件提供上游四模块示例，
  `identity → billing, notifications → reporting` 报“Build order 必须恰好包含每个模块一次”。
- 使用真实 `parallel_safety_gate.classify_group`，声明 `src/` 与 `src/file.py`，
  返回 `manual-parallel-eligible`、空 evidence。
- 以上是本地函数级复现，不是真实宿主或 GitHub/GitLab 端到端验收。
- 源码存在另一份解析：`sync-map-gitlab.sh` 内联按箭头拆序列；
  `spec-digest.py` 则使用兼容模式，`order` 当前代表表格行序。

## Input and Behavior Contract

### 1. 构建顺序和依赖

接受现有线性顺序与上游并列示例，支持 `→` / `->`、英文逗号、空白和 module id 反引号。
例如 `identity → billing, notifications → reporting` 表示三个声明组；组内保留展示顺序，
但不能凭展示次序把组内依赖当成合法。

- 每个模块恰好出现一次；空组、空元素、重复、未知模块、缺项均明确失败。
- 依赖必须来自前面的声明组；同组依赖、自依赖、循环和逆序依赖都失败。
- 模块表、声明组、稳定遍历序列和依赖层是不同概念，消费者不得混用。
- `Depends on` 是依赖事实源。声明组用于验证构建顺序，不额外生成模块间阻塞边。
- readiness 保留按依赖层提取只读候选的语义；即使线性列出的两个模块无依赖，
  也只能说“值得审查”，不能说用户已选择并行。说明候选不代表任务可立即领取。
- 缺失 Build order 的旧快照仍可用于兼容摘要读取，不能因此取得严格执行输入资格。

### 2. 解析消费者与摘要兼容

严格工作流共用 `capability_map.py` 的图验证和顺序语义，不再各自拆解逗号/箭头。
实施计划应逐项登记调用方，包括 readiness、安全门、guidance、GitLab 同步预览、
Desktop 只读预览、GitHub 同步指引以及摘要/历史读取。

- 对同一合法样例，消费者识别相同的模块集合、依赖、声明顺序；严格消费者拒绝同样的坏图。
- 串行同步可以按组展开稳定序列，但不能把组内顺序转成依赖，也不能并发建远端 Issue。
- 摘要的 `goalDigest` / `rowDigest` 算法仍只在 `spec-digest.py` 中实现。
- 保持已有合法文档的摘要稳定，包括旧快照缺少 Build order 的情形。
- 保留摘要 `order` 的旧语义，不直接将表格行序字段改造成执行顺序；严格消费者使用明确的图解析结果。
- 若确需改变规范化算法或数据格式，先说明版本化和显式迁移方案，再请用户确认。
  不能通过重写 state、历史或清除 digest 来隐藏真实漂移。
- 同步中断恢复、GitLab 幂等与远端身份修复属于后续 #141；本模块只改变其解析接缝，
  不把预览通过写成完整同步安全。

### 3. 显式边界检查

保留五字段声明：paths、publicInterfaces、migrations、globalConfig、testResources。
既有冲突分类保持可解释；`manual-parallel-eligible` 仅表示声明层未发现冲突。

- 对合法仓库相对路径，归一化尾斜杠、重复分隔符、`.` 段后按路径组件判等或父子关系。
  `src/`、`./src`、`src//` 与 `src/file.py` 不能漏报包含；`src` 与 `src-old` 不能误判包含。
- 根路径 `.` 覆盖全仓库，不能当成互不相关的名字。
- 空值、父目录穿越、绝对路径、盘符/UNC、反斜杠歧义、通配符与控制字符不进入 eligible。
- 大小写或 Unicode 别名无法证明互异时返回 needs-review；不假设所有平台都区分大小写。
- 路径涉及符号链接、失效链接、仓库外目标或权限不足时，保守返回 needs-review，
  不通过跟随链接读取仓库外内容来取得“安全”证据。
- 尚未创建的普通相对路径允许参与词法比较，但报告不将它描述为已验证的物理隔离。
- CLI 解析入口与直接库调用同样校验字段类型和路径；异常对象不得绕过验证或崩溃成假绿。
- 报告保留原声明、可判断时的规范路径、受影响模块与原因；信息不足必须可观察。

## Tech Stack and Project Structure

现有 Python 3 标准库、Git、macOS `/bin/bash` 3.2；不新增依赖、守护进程、数据库或宿主 API。

- `plugins/spec-guard/hooks/capability_map.py`：共享图解析。
- `plugins/spec-guard/hooks/spec-digest.py`：唯一摘要实现及兼容读取。
- `plugins/spec-guard/hooks/parallel_safety_gate.py`：边界解析与分类。
- `plugins/spec-guard/hooks/parallel-readiness.py` 及现有预览/同步入口：消费者。
- `plugins/spec-guard/hooks/test-*.sh`：行为回归；`scripts/validate.sh`：常规门禁。
- `tasks/audit-map-consistency/plan.md`：规格批准后才生成；GitHub #140 下的 sub-issue 为任务事实源。
- `docs/research/`：验收证据；现有 README/兼容说明/CHANGELOG：更新对外语义。

## Code Style

沿用标准库、snake_case、显式错误和小函数；不复制 parser/hash，不改无关格式。
现有分类风格示例（不是待复制的另一套判据）：

```python
return {"classification": "needs-review", "evidence": [
    {"category": "missing-boundary", "modules": missing}
]}
```

## Commands and Testing Strategy

规格批准、实施时先写失败回归，再修复；只读诊断期间不得触发远端创建或 worker 启动。
从仓库根运行现有命令：

```bash
python3 plugins/spec-guard/hooks/spec-digest.py --selftest
/bin/bash plugins/spec-guard/hooks/test-parallel-readiness.sh
/bin/bash plugins/spec-guard/hooks/test-parallel-safety-gate.sh
/bin/bash plugins/spec-guard/hooks/test-parallel-guidance.sh
/bin/bash plugins/spec-guard/hooks/test-sync-map-gitlab.sh
/bin/bash plugins/spec-guard/hooks/test-claude-desktop-mcp.sh
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
```

测试层次：纯 parser 正反例；临时 Git 仓库内路径与链接；真实命令/预览配合 gh/glab 桩；
升级前后摘要黄金样例与 hook 输出；隔离副本中的反向/变异测试。每项新增防线须证明旧行为会失败。
测试文件名和接入位置在正式计划中明确，不只测试 Markdown 里是否存在某个字符串。
本机文件系统测试不冒充四端原生、Windows 或真实 GitLab 同步验收；后者由 #143 汇总。

## Success Criteria

1. AC1 / F12：上游并列样例与既有线性样例通过，坏图矩阵被全部拒绝，组内依赖不能靠展开顺序漏过。
2. AC2 / F12：所有解析消费者有接缝测试，遍历与摘要字段语义不混用，无额外远端写入。
3. AC3 / F12：旧摘要黄金样例不漂移，真实目标/职责变化仍能被检测，旧无序快照不获严格有效资格。
4. AC4 / F05：已知父子/等价路径冲突必报；明确不相交的普通路径仍可通过声明层检查。
5. AC5 / F05：大小写、符号链接、非法输入和直接库入口反例不产生 eligible，诊断明确且不读外部内容。
6. AC6：常规门禁包含新增回归；原反例和故意退回旧判据的实现使测试失败，正常串行无回归。
7. AC7：文档区分格式、候选、声明边界和运行安全；暂停写入口不被重新开放，四端证据不互相代替。

## Boundaries

- Always：保留原始历史、用户文件和映射；只读检查不修改工作区或远端；不确定就明确降级；每个任务单独测试提交。
- Ask first：摘要算法/状态 schema 的不兼容变更、扩大格式语法、改变候选含义、真实远端写入、放宽暂停限制、发布。
- Never：实现自动调度/多 activeModule；自动启动或登记 Agent；自动创建 worktree、合并、回收；静默迁移历史；修改或 vendored 上游。

## Review Gate

规格语义和范围已确认，尤其“声明组与依赖层分开”“摘要兼容保留”“物理边界不确定时需人工审查”。
已批准 [实施计划](../tasks/audit-map-consistency/plan.md)，task #159–#173 按序推进；各检查点及交付仍需验证。
规格批准不表示 F05/F12 已修复或已经完成验收。
