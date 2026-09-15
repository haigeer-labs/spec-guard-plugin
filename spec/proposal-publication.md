# Spec: proposal-publication

## Objective

让后续评审只消费已经合并到一个 Git remote 默认分支的 Proposal。发布器将一次远端默认分支快照固定为 `reviewCommit`，从该快照读取指定 Proposal 和能力图，再以 Proposal 声明的 baseline commit 复核 `proposal-contract`。它把“本地有一个看似合理的文件”与“远端默认分支有一份可评审事实”明确分开。

本模块不读取 GitHub/GitLab Issue，不创建或修改 Proposal、能力图、Issue、PR、分支、任务或 `.agent/state.json`，也不调用 `spec-github-bridge` 或 `/sync-map`。

## Publication contract

### Input

调用方显式提供项目根目录、Proposal id 和 Git remote 名称。Proposal id 使用 `proposal-contract` 的 grammar；remote 名称只用于从项目 Git 配置取得 transport URL，不是需求事实。

发布器以 `git ls-remote --symref <remote-url> HEAD` 解析远端默认分支的完整 `refs/heads/<name>` 与其 commit。它不会使用本地 `refs/remotes/<remote>/HEAD`、`main`/`master` 猜测、当前分支或当前 checkout 作为替代。

### Atomic remote snapshot

- 在系统临时目录创建 bare repository；所有 `git fetch`、`git show`、`git merge-base` 都只针对该临时仓库，绝不写入调用方项目或其其他 worktree。
- 抓取默认分支后，抓到的 tip 必须仍等于最初由 `ls-remote` 观察到的 commit；不相等表示远端在读取间移动，结果为 `unknown`，不得改用新的 tip。
- `reviewCommit` 是这个验证一致的 tip。Proposal 文件必须存在于 `reviewCommit:spec/proposals/<proposal-id>.md`；不存在时结果为 `absent`，这表示尚未发布而不是格式错误。
- 任何用于评审的能力图都从此临时快照的 Git object 读取。不得从调用方工作树、暂存区、未提交文件或 sibling worktree 读取相同路径来补全或替代内容。

### Baseline provenance and validation

- 读取 Proposal 后，`Baseline.remote` 必须等于调用方 remote 名称，`Baseline.default_branch` 必须等于远端 HEAD 解析出的短分支名。
- `Baseline.commit` 必须是 `reviewCommit` 在该远端默认分支快照中的祖先。发布器在临时仓库中验证祖先关系并从该 commit 读取 `spec/CAPABILITY-MAP.md`。
- 将该 baseline map 与 Proposal 交给 `proposal_contract.validate_proposal`；它是唯一的 Proposal grammar、marker、digest、module-id、依赖与锚点校验来源。发布器不复制其解析、摘要或 marker 算法。
- 同时从 `reviewCommit` 读取当前能力图并以既有严格 capability-map parser 验证。返回结果包含 baseline 与 review 两份 immutable map 文本，以及已解析 Proposal；临时路径绝不从 API 泄漏出去。

### Result model

| State | Meaning |
| --- | --- |
| `published` | 已得到一致的远端默认分支快照；Proposal、baseline map、review map 与契约均有效。 |
| `absent` | 一致的远端默认分支快照中没有精确 Proposal 路径。 |
| `invalid` | Proposal 存在，但它的格式、remote/branch/commit provenance、祖先关系或任一能力图不合法。 |
| `unknown` | 无法安全完成只读观察，例如 remote 未配置、HEAD 无法解析、transport 失败、远端在观察期间移动或 Git 工具失败。 |

`invalid` 不能被降级为 `unknown`；`unknown` 也不能被描述为“远端已经核验”。所有错误诊断都必须避免回显含认证材料的 remote URL。

## Commands

```text
python3 -B plugins/spec-guard/hooks/test_proposal_publication.py
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
```

## Project structure

```text
plugins/spec-guard/hooks/proposal_publication.py      -> Git-only remote snapshot and result model
plugins/spec-guard/hooks/test_proposal_publication.py -> local bare-remote regressions and failure stubs
plugins/spec-guard/hooks/proposal_contract.py         -> reused static Proposal contract validator
plugins/spec-guard/hooks/capability_map.py            -> reused strict capability-map parser
plugins/spec-guard/references/proposal-publication.md -> caller-facing read-only behavior and JSON result guide
```

## Testing strategy

- 使用临时普通仓库和本地 bare remote；测试真实执行 Git 传输，但不访问网络或真实 GitHub/GitLab。
- 正向覆盖：远端 HEAD 为非 `main` 名称、Proposal 与 baseline 位于远端默认分支历史、review commit 被固定、调用方 worktree 同路径存在不同未提交 Proposal/能力图而结果仍只反映远端内容。
- 反向覆盖：没有 remote、无默认 HEAD、缺少 Proposal、畸形 Proposal、baseline 的 remote 或默认分支不匹配、baseline commit 不属于默认分支历史、baseline/review map 损坏、远端 tip 在读取间移动和任何 Git 子命令失败。
- 断言临时目录被清理、调用方 `.git` refs、working tree、`.agent/state.json` 与 Issue/PR/task 相关文件字节不变；stub 记录的 Git 参数不得包含 shell 字符串或写入调用方项目的命令。
- 本模块不引入浏览器 UI，浏览器验收不适用。

## Boundaries

- Always: 使用显式 remote、远端 HEAD 与临时 bare snapshot；固定并返回 `reviewCommit`；用 `proposal-contract` 和 `capability_map` 的现有实现验证；失败时保守地返回诊断状态。
- Ask first: 支持非 Git transport、改变 `spec/proposals/` 的发布路径、缓存远端内容、在项目内写入 fetch ref、改变 `reviewCommit` 固定规则或把 `unknown` 当可评审结果。
- Never: 从当前 worktree 或其未提交文件读取 Proposal/能力图事实；调用 tracker API；创建或修改 Issue、PR、分支、任务、能力图、Proposal 或 `.agent/state.json`；调用 `spec-github-bridge`、`/sync-map` 或旧 bridge 生命周期。

## Success criteria

- 远端默认分支的单次一致快照是唯一可返回的已发布 Proposal 来源，且返回的 `reviewCommit` 可审计。
- 已发布 Proposal 的 baseline 必须被证明来自同一远端默认分支历史；不能由本地文件、另一个 remote 或任意可达 commit 冒充。
- 已发布、尚未发布、无效和无法核验四种结果互斥且可观察；没有结果被误报为已发布。
- 所有副作用局限在可清理的系统临时目录；用户项目和所有远端协作对象保持不变。

## Open questions

无阻塞问题。Proposal Issue marker、标签与 GitHub/GitLab 只读查询由 `proposal-tracker-read` 处理；综合的 ready/stale/blocked/unknown 评审由 `proposal-review` 处理。
