# Plan: proposal-review

Spec: `spec/proposal-review.md`

## Overview

实现一个纯聚合器，输入已固定的 Publication 与只读 TrackerRead，输出阶段解释或明确的阻断状态。它不执行 Git/tracker transport：publication 与 tracker-read 已分别拥有这两个边界，review 只验证两者可被安全组合以及远端 review map 对 Proposal baseline 的影响。

本计划不创建 Issue、tracker task、PR、分支或 `.agent/state.json`；本 initiative 的用户约束禁止自动操作 GitHub/GitLab。计划仅记录在此文件，不复制到 tracker。

## UI acceptance scope

No browser UI is introduced. This module exposes Python/JSON read results only, so browser acceptance is not applicable.

## Architecture decisions

- `Publication.published` 是唯一允许进入阶段解释的 Git 事实；非 published 状态优先返回同名阻断状态。
- `TrackerRead.verified` 是唯一允许进入阶段解释的 tracker 事实；review 不重新查询 tracker，也不从 title/number 推断身份。
- freshness 是 review map 相对 Proposal baseline 的最小语义检查：同名候选已存在、目标/基线 row 漂移、依赖或 anchor 不再可证明均为 `stale`；无关新模块不应制造假 stale。
- 结果不合并为跨服务“原子快照”：保留 `reviewCommit` 与 tracker identity，未来 Promotion 必须显式重新调用 review。
- JSON 只提供 stable facts 与诊断码；publication/tracker 的正文、URL、token 与异常文本不外泄。

## Implementation slices

### Slice 1: Establish in-memory review fixtures and precedence matrix

**Acceptance criteria:** Focused tests construct publication/tracker result objects without Git or CLI. They define five stage states, four blocking states and precedence (`stale` before stage).

**Verification:** `python3 -B plugins/spec-guard/hooks/test_proposal_review.py` fails before implementation, while proving no filesystem or external transport is required.

**Likely files:** `plugins/spec-guard/hooks/test_proposal_review.py`.

**Dependencies:** `proposal-publication`, `proposal-tracker-read`.

### Slice 2: Implement pure freshness and result aggregation

**Acceptance criteria:** Small helpers parse supplied map bytes, reuse digest/parser contracts, and emit correct states for clean review, same-id absorption, baseline digest drift and dependency/anchor invalidation.

**Verification:** Fixture suite proves unrelated new modules do not cause stale, while every relevant drift blocks stage interpretation. No helper opens a project path or runs a subprocess.

**Likely files:** `plugins/spec-guard/hooks/proposal_review.py`, focused tests.

**Dependencies:** Slice 1.

### Slice 3: Add safe JSON and caller guidance

**Acceptance criteria:** Serialization retains only review commit, proposal/tracker identifiers, state/stage and stable diagnostics. Reference guidance explains `accepted` versus `promoted-claim`, and the need to re-review before Promotion.

**Verification:** Tests reject marker/body/token/URL leakage; focused test joins `/bin/bash scripts/validate.sh` and the full repository suite passes.

**Likely files:** `plugins/spec-guard/hooks/proposal_review.py`, `plugins/spec-guard/hooks/test_proposal_review.py`, `plugins/spec-guard/references/proposal-review.md`, `scripts/validate.sh`.

**Dependencies:** Slice 2.

### Checkpoint: Review result is informative but non-mutating

- Publication and tracker failure states stay distinct from `rejected` and `stale`.
- Stage interpretation is impossible without the published remote snapshot and verified Issue.
- No result becomes an automatic approval or Promotion proof.
- No code path writes a local/remote workflow object or calls the old bridge.

## Dependency graph

```text
in-memory result/precedence fixtures
                ↓
publication + tracker aggregation with map freshness
                ↓
safe JSON, guidance and full quality gate
```

Freshness must precede stage interpretation: an Issue can retain `accepted` while its Proposal is already obsolete in the remote review map.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| `accepted` is mistaken for automatic promotion | Keep it a descriptive result and name post-promotion label `promoted-claim`; document re-review requirement. |
| Local map/worktree leaks into review | Accept only map text carried by a published Publication; use in-memory fixtures to prove no path/transport access. |
| Unrelated map growth causes false stale | Compare Proposal baseline goal/rows/dependencies/anchor, not raw whole-map equality. |
| Tracker stage changes after Git snapshot | Expose both identities and require a fresh review before Promotion; never claim atomicity. |
| Diagnostics leak remote or issue content | Map internals to stable codes in serializer tests. |
| Aggregator grows transport behavior | Restrict imports to completed Proposal modules and capability-map/digest helpers; tests reject subprocess/CLI use. |

## Current checkpoint

**Type:** implementation complete; awaiting review.

**Reviewable artifacts:** `spec/proposal-review.md`, this plan, `plugins/spec-guard/hooks/proposal_review.py`, `plugins/spec-guard/hooks/test_proposal_review.py`, `plugins/spec-guard/references/proposal-review.md` and `scripts/validate.sh`.

**Completed:** The focused fixture contract defines all stage interpretations, publication/tracker blocking precedence and `stale` precedence for a map that already contains the proposed module. The pure aggregation reuses the strict capability-map parser and `spec-digest.py` over Publication-supplied snapshot text; it blocks module absorption, baseline goal/row drift, and dependency/anchor order drift while allowing unrelated new modules. Safe JSON emits only review/tracker identity and stable diagnostics. Caller guidance is present, the focused six-test suite is part of `scripts/validate.sh`, and the full validator passes.

**Next step:** Review the local diff. On explicit direction, begin `proposal-promotion-proof` with a new module Spec; do not create, modify or migrate any Proposal Issue during that design step.

**Stop condition:** A request to mutate tracker stages, treat acceptance as automatic promotion, consume local/cached maps, or unify old bridge state requires an explicit new design decision.
