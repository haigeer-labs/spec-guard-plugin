# Spec: proposal-tracker-read

## Objective

为已由 `proposal-publication` 固定的 Proposal 提供最小的 GitHub/GitLab **只读** Issue 核验器。它在调用方明确指定的 GitHub repository 或 GitLab project 内，按 Proposal 的完整 identity marker 恢复唯一普通 Proposal Issue，并核验 `proposal` 身份标签和唯一阶段标签。结果供后续 `proposal-review` 消费，不把 tracker 事实复制到本地状态。

本模块不从 Issue 标题、编号、当前 Git remote、能力图或本地 worktree 推断身份；也不创建、修改、关闭或标记任何 Issue、PR、分支、任务、Proposal、能力图或 `.agent/state.json`。它不调用或依赖 `spec-github-bridge` 或 `/sync-map`。

## Read contract

### Explicit scope and inputs

- 调用方必须显式提供 tracker kind（仅 `github` 或 `gitlab`）和目标容器：GitHub 为精确 `owner/repository`，GitLab 为可验证的 project id；不得从本地 remote、Issue URL、标题或搜索结果反推。
- 调用方提供已解析的 `proposal_contract.Proposal`，其完整 marker 是唯一搜索键。adapter 不重新实现 Proposal Markdown grammar 或 marker 生成。
- transport 只能执行平台的认证检查和 Issue/read-search 请求。所有命令使用 argv；不得调用 Issue/PR/label/discussion 写入端点、`git` 写入操作、旧 bridge、slash command 或 state helper。

### Candidate recovery

- 搜索命中只是一组候选；只有 Issue 正文的独立一行与 Proposal marker 完全相等才是匹配。标题、Issue 编号、URL、部分 marker、code fence 文本或相似 Proposal id 永远不能恢复身份。
- 必须证实搜索结果已经完整遍历：平台分页、截断标志、游标或响应 schema 不能判定时，adapter 返回 `unknown`。不能因第一页刚好有一个候选而接受它。
- 完整读取后没有精确正文匹配为 `absent`；超过一个精确匹配为 `invalid`。任何精确匹配若不属于显式目标 repository/project，也为 `invalid`。
- 命中对象必须是普通 Issue，且其正文不得包含 legacy `spec-guard-sync:v2` identity marker；它不是 initiative、module 或 task 的旧 bridge 投影。

### Tracker validation

- adapter 把恢复出的完整正文与标签名交给 `proposal_contract.validate_tracker`。该函数是 Proposal marker、`proposal` 身份标签以及唯一 `proposal-stage:*` 标签的唯一校验来源。
- GitHub/GitLab 响应若缺少可验证的正文、标签、普通 Issue 标识或目标容器标识，属于 `unknown`；已读到的字段与契约冲突（重复 marker、错标签、legacy marker）属于 `invalid`。
- Issue state、标题、作者、评论、里程碑、assignee 和 discussion 内容不属于 v1 阶段事实，不能改变核验结果。评论只可由后续明确模块单独读取。

## Result model

| State | Meaning |
| --- | --- |
| `verified` | 在显式目标容器中完整恢复唯一普通 Issue，且正文及标签通过 Proposal tracker contract。 |
| `absent` | 平台已完整读取，但没有该完整 marker 的正文匹配。 |
| `invalid` | 已取得的候选或 tracker 字段违反唯一性、目标容器、普通 Issue 或 Proposal tracker contract。 |
| `unknown` | 认证、网络、CLI、分页完整性或响应 schema 无法安全核验。 |

每个结果仅携带安全的结构化事实（platform、目标容器、Issue number/IID、阶段、诊断）；不得回显 token、完整 API URL、Issue 正文或评论。`verified` 不是批准、晋级、任务创建或远端默认分支发布的证明。

## Commands

```text
python3 -B plugins/spec-guard/hooks/test_proposal_tracker_read.py
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
```

## Project structure

```text
plugins/spec-guard/hooks/proposal_tracker_read.py      -> GitHub/GitLab read-only adapter and result model
plugins/spec-guard/hooks/test_proposal_tracker_read.py -> fixture-driven positive/negative regressions
plugins/spec-guard/hooks/proposal_contract.py          -> reused marker and label validator
plugins/spec-guard/hooks/gitlab_tracker.py             -> prior strict recovery pattern only; no write-client reuse
plugins/spec-guard/references/proposal-tracker-read.md -> caller-facing read-only semantics
```

## Testing strategy

- 使用 runner stub 和 GitHub/GitLab JSON fixtures；不访问网络、不需要真实登录、不创建或修改 tracker 对象。
- 正向覆盖：两个平台各有一个目标容器内、正文完整 marker、`proposal` 与单一有效阶段标签的普通 Issue，并返回 `verified`。
- 反向覆盖：标题或部分 marker、缺正文、重复完整 marker、外部容器 marker、legacy bridge marker、缺/重复身份或阶段标签、未知阶段、分页不完整、畸形 JSON、CLI/认证/网络失败。
- 断言每个 transport argv 都是只读查询；`scripts/validate.sh` 包含 focused test；测试前后工作树、`.agent/state.json` 与 fixture 外的文件不变。
- 本模块不引入浏览器 UI，浏览器验收不适用。

## Boundaries

- Always: 显式平台与容器、完整 marker、完整分页和唯一性；复用 `proposal_contract.validate_tracker`；让不可验证的远端观察返回 `unknown`。
- Ask first: 支持其他 tracker、从 Git remote 推断容器、读取评论作为评审事实、缓存 tracker 数据、增加新的标签/阶段或改变普通 Issue 判定。
- Never: 创建或修改 Issue、标签、评论、PR、分支、任务、Proposal、能力图或 `.agent/state.json`；调用 `spec-github-bridge`、`/sync-map`、旧 bridge 写入客户端；把搜索标题、编号、局部结果或其他 worktree 文件当身份或需求事实。

## Success criteria

- GitHub 和 GitLab 都只能在显式目标容器内，用完整正文 marker 恢复唯一 Proposal Issue。
- `verified`、`absent`、`invalid` 与 `unknown` 互斥，且网络/分页不确定性绝不伪装为 `absent` 或 `verified`。
- 唯一可变阶段事实仍是符合 `proposal-contract` 的单一标签；不会写回本地或远端。
- 新 adapter 与旧 bridge 的状态、命令和副作用完全隔离。

## Open questions

无阻塞问题。GitHub/GitLab 具体 CLI 的只读查询形态与分页响应，将在实现切片的 fixture-first 测试中固定；若平台无法提供可证实的完整候选集，保持 `unknown` 而非放宽身份规则。
