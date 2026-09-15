# Spec: proposal-boundary-guidance

## Objective

在“模块交付”或“推进到下一模块”这两个显式边界，提供不阻断的 Proposal 提醒与三个只读入口：intake、review、promotion proof。它帮助调用方把新发现的独立需求与当前实现工作分离，但不创建候选池、任务、Issue、PR、分支或本地状态。

## Contract

- 入口接收调用方显式提供的 boundary：`module-deliver` 或 `module-advance`。这两种事件返回 `reminder` 和固定顺序的入口提示；其他已知工作事件返回 `not-applicable`，无效输入返回 `invalid`。提醒永远不阻止交付或推进。
- `intake` 只指向 `proposal-contract` 的文档契约：未进入远端默认分支的草稿只是本地设计，不能被提示解释为共享候选或任务。
- `review` 指向固定顺序 `proposal-publication` → `proposal-tracker-read` → `proposal-review`。只有远端默认分支 snapshot 与 GitHub/GitLab 的只读 Issue/讨论事实可以参与；本地、缓存、其他 worktree 或标签猜测都不能替代。
- `promotion-proof` 指向一次新的 accepted review 后的 `proposal-promotion-proof`；`accepted` 与 `promoted-claim` 都不自动授权或回写任何对象。
- 结果仅含 state、boundary 与稳定 entry id。不得包含需求正文、Proposal 内容、能力图、Issue/评论、URL、token、临时路径或原始异常。

## Commands

```text
python3 -B plugins/spec-guard/hooks/test_proposal_boundary_guidance.py
/bin/bash scripts/validate.sh
```

## Project structure

```text
plugins/spec-guard/hooks/proposal_boundary_guidance.py      -> pure boundary/event guidance
plugins/spec-guard/hooks/test_proposal_boundary_guidance.py -> in-memory event and JSON regressions
plugins/spec-guard/references/proposal-boundary-guidance.md -> caller-facing entry and non-blocking guidance
```

## Testing strategy

- 以纯内存输入覆盖两个允许 boundary、非 boundary 事件、非法输入、稳定 entry 顺序与 JSON 脱敏；不运行 Git、`gh`、`glab` 或网络。
- 测试确认所有路径不读取/写入 worktree、能力图、Proposal、Issue、标签、任务、分支或 `.agent/state.json`。
- focused suite 加入 `scripts/validate.sh`；完整校验在实现完成时运行。

## Boundaries

- Always: 仅在显式模块交付/推进边界给出可忽略提醒；把共享事实限制为远端默认分支和 tracker 的只读观察；明确 intake、review、proof 的顺序与重新评审要求。
- Ask first: 增加新的提醒时机、把提醒接入旧命令或 hook、持久化/枚举候选、自动调用远端读取、改变入口顺序或阶段语义。
- Never: 调用 `spec-github-bridge`、`/sync-map` 或旧 bridge；自动创建/修改 Issue、讨论、PR、分支、任务、Proposal、能力图或 `.agent/state.json`；把提醒、`accepted` 或 `promoted-claim` 当作批准、交付或晋级证明。

## Success criteria

- 两个约定边界可获得简洁、非阻断且顺序稳定的入口提示；其他时机不产生需求池提醒。
- 每条入口都清楚限制事实来源与下一步，不能把本地或未提交内容伪装成共享 Proposal。
- Guidance 层不产生流程副作用，也不重新实现或绕过前序 Proposal 契约。

## Open questions

无阻塞问题。若未来需要将提醒接入既有 `/deliver`、`/next` 或 hook，须先单独设计其与旧 bridge、状态和用户可见输出的边界。
