# Spec: proposal-contract

## Objective

定义 Candidate Proposal Pool 的第一份可机器核验契约。正在实现既有模块的人可以把一个独立、尚未进入能力图的需求写成 Proposal；该 Proposal 在合并到远端默认分支后，才是后续发布、tracker 只读核验与评审可使用的候选事实。

v1 只承载新增独立模块（`new-module`）。它不创建或修改 Issue、PR、分支、任务、能力图或 `.agent/state.json`，也不调用或依赖 `spec-github-bridge` 或 `/sync-map`。

## Contract

### Proposal document

- 已发布 Proposal 的固定位置为 `spec/proposals/<proposal-id>.md`；`proposal-id` 必须匹配 `^[a-z][a-z0-9-]{2,62}$`。
- 文档首行必须是非空的 `# Proposal: <title>`，随后必须恰好有一行完整 identity marker：

  ```html
  <!-- spec-guard-proposal:v1 id=<proposal-id> -->
  ```

- 文档必须恰好包含 `## Summary`、`## Capability map baseline`、`## Change` 与 `## Tracker contract` 四个顶级段；自由文本只允许在 `Summary` 中。解析器忽略 fenced code block 中看似相同的标题、marker 或表格。
- `Summary` 说明问题、受影响边界与为什么它是独立能力；它不是能力图、Issue 或实现任务的复制品。

### Capability-map baseline

`Capability map baseline` 是 Proposal 写作时已合并共享事实的摘要，不是从当前 worktree 推断的结果。它必须逐项记录：

| Field | Required value |
| --- | --- |
| Remote | 用于解析默认分支的 Git remote 名称 |
| Default branch | 远端默认分支名，不带 `refs/` 前缀 |
| Commit | 解析后的完整 Git object id（40–64 位小写十六进制） |
| Capability map | 固定为 `spec/CAPABILITY-MAP.md` |
| Goal digest | 该 commit 中能力图 `## 目标` 的 `spec-digest.py` 12 位摘要 |
| Module digests | 一张含全部基线 module id 及其 `spec-digest.py` row digest 的表，id 不重复 |
| Build order | 该 commit 中能力图的完整、逐字 Build order 表达式 |

- 唯一允许的 digest 算法是仓库的 `hooks/spec-digest.py`；不得在新代码中复制、内联或用另一种哈希替换它。
- 该摘要必须能由 `Commit` 所指的远端默认分支版本完全复算。当前 checkout、其他 worktree、暂存区和未提交文件都不能补全、修正或替代其中任一字段。
- Proposal 文档的本地存在不构成发布。`proposal-publication` 负责以后续固定远端 commit 验证这条契约。

### Supported change type: `new-module`

v1 中 `Change` 段只允许下面的字段：

| Field | Rule |
| --- | --- |
| Type | 固定为 `new-module` |
| Module id | 满足能力图 module-id 语法，且不在基线模块表中 |
| Responsibility | 非空、单行，描述该模块而非实现步骤 |
| Depends on | `—` 或由逗号分隔、无重复的基线 module id |
| Build-order anchor | `after:<module-id>` 或 `end`；`after` 的对象必须是基线模块 |

- 所有依赖必须在结果 Build order 中位于新模块之前；当使用 `after:<module-id>` 时，锚点也必须位于新模块之前且不早于所有依赖。无法由 Proposal 自身证明这一点时，验证结果为 `invalid`，而不是猜测一个位置。
- 修改既有模块、删除模块、重排既有模块、批量 Proposal 和没有锚点的 Proposal 在 v1 中都不受支持，必须被明确拒绝。后续若扩展类型，须以新的版本化契约新增，不能放宽 `v1` 的解析规则。

### Tracker contract

- 一份 Proposal 对应普通 Proposal Issue，不是 initiative、module 或 task Issue；tracker 在本模块中只是未来的只读讨论与阶段来源。
- Issue 正文必须恰好含一行与 Proposal 文档完全相同的 identity marker。按完整 marker 查找时，目标 GitHub repository 或 GitLab project 内必须恰好匹配一个普通 Issue；零个、多个、部分 marker 或来自别处的结果均不构成身份。
- Issue 标签必须恰好有一个身份标签 `proposal`，并恰好有一个阶段标签：`proposal-stage:draft`、`proposal-stage:published`、`proposal-stage:in-review`、`proposal-stage:accepted`、`proposal-stage:rejected` 或 `proposal-stage:promoted`。
- 阶段标签是唯一的可变阶段事实；Proposal 文档不镜像当前阶段，`.agent/state.json` 也不记录候选池。任何标签或 Issue 的创建、修改与阶段转换都由人或后续明确授权的流程完成，不由本能力自动执行。

## Result model

本模块的解析与校验入口只处理本地给定的 Markdown、已固定的能力图内容和显式 tracker 响应；不执行网络写入。结果为：

- `valid`：文档语法、marker、基准摘要与 `new-module` 静态关系都一致。
- `invalid`：缺失、重复、未知或互相矛盾的字段；结果给出逐项诊断，绝不选择“最像”的值。
- `unknown`：只有后续 publication 或 tracker-read 在远端提交不可得、默认分支无法解析或只读服务不可用时使用；本地格式错误不能降级为 `unknown`。

## Commands

```text
python3 -B plugins/spec-guard/hooks/test_proposal_contract.py
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
```

## Project structure

```text
spec/proposals/<proposal-id>.md              -> 已发布 Proposal 的规范位置
plugins/spec-guard/references/proposal-contract.md -> 面向使用者的字段与示例说明
plugins/spec-guard/hooks/proposal_contract.py       -> 标准库、只读的 grammar/semantic validator
plugins/spec-guard/hooks/test_proposal_contract.py  -> 正反向回归
plugins/spec-guard/hooks/spec-digest.py             -> 唯一能力图摘要实现（复用，不复制）
```

## Testing strategy

- 用能力图 Markdown fixture 与 `spec-digest.py` 构造 baseline；测试绝不请求网络、选择 Git ref 或修改远端对象。远端默认分支解析属于后续 `proposal-publication`。
- 正向覆盖：没有依赖与 `end`、有多个基线依赖与 `after:<id>`、完整 marker、完整 baseline 摘要。
- 反向覆盖：非法 id、重复/部分 marker、缺段或 fenced 示例被误解析、未知字段、错误 digest、漏模块 digest、非默认分支或非完整 commit、已有 module id、重复依赖、非法锚点、锚点或依赖顺序冲突、非唯一阶段标签与不受支持的 change type。
- 验证运行入口不写 Proposal、能力图、Issue、`.agent/state.json` 或 Git refs；为该性质加入可观察的无变更断言。
- 本模块不引入浏览器 UI，浏览器验收不适用。

## Boundaries

- Always: 只把已固定远端默认分支 commit 的能力图作为可共享基准；完整匹配 marker 和单一阶段标签；复用 `spec-digest.py`；让歧义显式失败。
- Ask first: 新增 change type、改变 marker 或标签命名空间、接受非 `spec/proposals/` 路径、放宽 baseline 或唯一性规则。
- Never: 调用 `spec-github-bridge`、`/sync-map` 或其状态投影；把未提交 worktree 文件当作 Proposal 需求或基线；新建/修改 Issue、PR、分支、任务或 `.agent/state.json`；把 Proposal 自动晋级到能力图。

## Success criteria

- `new-module` Proposal 有单一、可跨 GitHub/GitLab 精确匹配的身份，并且 tracker 阶段不会在本地状态中复制。
- 每一条可评审基准都能回指到单一远端默认分支 commit；未提交 worktree 不能影响评审输入。
- 格式、基准、模块 id、依赖、锚点或标签的歧义都会明确失败；远端不可用则由后续只读模块标成 `unknown`。
- v1 以最小范围支持新模块，既不接管旧 bridge 生命周期，也不产生任何远端或本地工作流副作用。

## Open questions

无阻塞问题。Proposal 的远端定位与 commit 固定、GitHub/GitLab 的只读查询、综合评审、晋级证据和非阻断入口分别由能力图中的后续模块承担。
