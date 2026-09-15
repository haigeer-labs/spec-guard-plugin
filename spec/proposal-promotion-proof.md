# Spec: proposal-promotion-proof

## Objective

为一个已 `accepted` 且新鲜的 Proposal 提供只读晋级证明：证明某个远端默认分支 commit 首次包含 Proposal 声明的新增 module，并且该 commit 中的 capability map 满足声明的职责、依赖与 anchor。它不创建提交、PR、Issue、标签、分支、任务、能力图或 `.agent/state.json`。

## Contract

- 输入为一次新的 `proposal-review` 结果及其 Publication；只接受 `accepted`，并重新从远端默认分支固定 promotion commit，不能信任本地 checkout、缓存或 `promoted-claim` 标签。
- 在远端默认分支的 first-parent 历史中，promotion commit 是首次含该 module 的 commit；其 map 中 Proposal module id 必须恰好一次，责任、依赖和 Build order 位置必须与 `new-module` 声明一致；其 first parent 不得已包含该 id。任一条件失败为 `invalid`，远端/父提交无法安全读取为 `unknown`。
- 输出 `proved` 时包含 proposal id、review commit、promotion commit 与 module id；绝不把 `proved` 写回 tracker，且 `promoted-claim` 不是输入替代品。

## Commands

```text
python3 -B plugins/spec-guard/hooks/test_proposal_promotion_proof.py
/bin/bash scripts/validate.sh
```

## Boundaries

- Always: 固定远端默认分支快照、复用 proposal/publication/review/capability-map 契约、重新评审前不证明。
- Ask first: 接受非 accepted 阶段、证明多个 module、缓存/本地事实、回写 tracker 或能力图。
- Never: 调用 `spec-github-bridge`、`/sync-map` 或旧 bridge；创建/修改任何 Git 或 tracker 对象。

## Success criteria

- `proved` 可回指唯一远端默认分支 commit，且该 commit 是首次将完全匹配的 module 纳入 map。
- `invalid`、`unknown` 与未接受状态不伪装为晋级证明；所有路径只读。
