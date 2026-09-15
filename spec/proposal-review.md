# Spec: proposal-review

## Objective

将同一次已固定远端默认分支的 Publication 事实与一次只读 Proposal Issue 核验组合为可审计的评审结论。评审器只解释事实：Proposal 是否已发布、Issue 阶段是什么、以及 Proposal 的新增模块是否已被远端 review map 吸收或其基线依赖是否已漂移。它不创建批准、标签、任务、Issue、PR、分支、能力图或本地状态。

`accepted` 是 Issue 阶段标签的观察结果，不是自动晋级授权；`promoted` 也只是未证明的声明。可交付的能力图修改与提交证据由后续 `proposal-promotion-proof` 独立处理。

## Review contract

### Inputs and provenance

- 输入必须是 `proposal_publication.read_published` 的 `Publication` 结果和 `proposal_tracker_read.read_tracker` 的 `TrackerRead` 结果，以及调用方显式提供的 tracker platform/target。评审器不读取 Proposal 文件、能力图、工作树、其他 worktree、Git remote 或 tracker。
- 只有 `Publication.state == published` 且其中有已解析 Proposal、`reviewCommit`、baseline map 与 review map 时，才可继续评审。其余 publication state 原样阻断为 `absent`、`invalid` 或 `unknown`，不得用 tracker 成功补偿。
- Tracker `verified` 必须对应同一 Publication 中的 Proposal marker；`absent`、`invalid` 与 `unknown` 原样阻断，不能由本地标签、Issue 编号、标题或缓存替代。
- Git 与 tracker 不是分布式原子快照。结果必须保留 `reviewCommit`、平台、目标容器、Issue id 和阶段，明确它们是两次只读观察；在未来 Promotion 前必须重新评审。

### Freshness check

- 评审器只消费 Publication 返回的 immutable baseline/review map 文本，使用既有 `capability_map.py` 与 `spec-digest.py`，不复制 parser 或摘要算法。
- 若 review map 含有 Proposal `new-module` 的 module id，结果为 `stale`：该候选已不再是尚未进入能力图的新模块。
- 若基线目标 digest、任一基线 module row digest、Proposal 依赖或 anchor 的可验证关系在 review map 中不再成立，结果为 `stale`。review map 新增但不改写这些基线事实的无关模块不构成 stale。
- review map 结构损坏或摘要不能安全复算为 `invalid`；任何输入缺失/不可读均为 `unknown`，不把它解释为“未漂移”。

### Stage interpretation

| Preconditions | Review state |
| --- | --- |
| 已发布、tracker 已核验、基线仍新鲜，stage 为 `proposal-stage:draft` 或 `proposal-stage:published` | `awaiting-review` |
| 已发布、tracker 已核验、基线仍新鲜，stage 为 `proposal-stage:in-review` | `in-review` |
| 已发布、tracker 已核验、基线仍新鲜，stage 为 `proposal-stage:accepted` | `accepted` |
| 已发布、tracker 已核验、基线仍新鲜，stage 为 `proposal-stage:rejected` | `rejected` |
| 已发布、tracker 已核验、基线仍新鲜，stage 为 `proposal-stage:promoted` | `promoted-claim` |

`stale` 优先于阶段解释。评审器不对 `accepted` 或 `promoted-claim` 产生布尔许可，不自动把 `in-review` 改为 `accepted`，也不调整任何标签。

## Result model

结果是 `Review(state, review_commit, proposal_id, platform, target, issue_id, stage, diagnostic)`。安全 JSON 只可包含这些标识、稳定状态及稳定诊断码；不得包含能力图/Proposal/Issue 正文、评论、token、remote/API URL、临时路径或原始异常。

允许状态为 `awaiting-review`、`in-review`、`accepted`、`rejected`、`promoted-claim`、`stale`、`absent`、`invalid`、`unknown`。其中只有前五种表示已发布且 tracker 已核验；后四种绝不表示可评审或可晋级。

## Commands

```text
python3 -B plugins/spec-guard/hooks/test_proposal_review.py
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
```

## Project structure

```text
plugins/spec-guard/hooks/proposal_review.py      -> pure publication/tracker aggregation and freshness checks
plugins/spec-guard/hooks/test_proposal_review.py -> in-memory fixtures and positive/negative regressions
plugins/spec-guard/hooks/proposal_publication.py -> reused immutable remote-default publication result
plugins/spec-guard/hooks/proposal_tracker_read.py -> reused verified read-only tracker result
plugins/spec-guard/references/proposal-review.md -> caller-facing result and re-review guidance
```

## Testing strategy

- 使用 publication/tracker object 与 map fixture；不运行 Git、`gh`、`glab` 或网络，不读取本地 Proposal/能力图路径。
- 正向覆盖全部五个阶段解释，及 review map 存在无关新增 module 时仍保留阶段结果。
- 反向覆盖 publication/tracker 的 `absent`、`invalid`、`unknown`，同名 module 已出现、目标/row digest 漂移、依赖/anchor 消失、损坏 map、缺失 snapshot、错误 marker/平台/target 对应，以及 JSON 脱敏。
- 测试前后断言没有 Issue、标签、PR、分支、任务、能力图、Proposal 或 `.agent/state.json` 写入；focused suite 加入 `scripts/validate.sh`。
- 本模块不引入浏览器 UI，浏览器验收不适用。

## Boundaries

- Always: 只消费已固定 Publication 和只读 tracker 结果；保留 `reviewCommit`；复用现有 parser/digest/contract；把漂移、歧义和不可验证事实显式化。
- Ask first: 增加新的阶段语义、把 `accepted` 解释为自动许可、接受本地/cached facts、跨服务时间窗口放宽、将 review 结果写回 tracker 或能力图。
- Never: 调用 `spec-github-bridge`、`/sync-map` 或旧 bridge；新建/修改 Issue、标签、评论、PR、分支、任务、Proposal、能力图或 `.agent/state.json`；把 `promoted-claim` 当 Promotion proof。

## Success criteria

- 每个可评审状态都能回指到固定远端 review commit、明确 Proposal id、目标 tracker 与唯一阶段事实。
- 已进入 review map 或依赖基线漂移的候选不能以任何 Issue 阶段伪装为新鲜。
- tracker/publication 不可用、缺失或无效与真正的 `rejected`、`stale` 明确区分。
- 评审层保持纯只读和可重算，不产生对人或远端系统的流程副作用。

## Open questions

无阻塞问题。Promotion 时应证明哪个提交将哪个已接受且新鲜 Proposal 纳入能力图，由后续 `proposal-promotion-proof` 定义。
