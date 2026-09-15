# Plan: proposal-publication

Spec: `spec/proposal-publication.md`

## Overview

实现一个 Git-only、只读的 Publication reader：它以远端 HEAD 的一次一致快照为唯一输入，固定 `reviewCommit`，读取指定 Proposal 和两份能力图（Proposal baseline 与 review snapshot），并把静态契约校验委托给已完成的 `proposal-contract`。

本计划的切片仅记录本模块实现顺序，不创建 GitHub/GitLab Issue、任务、分支、PR 或 `.agent/state.json`。Git transport 在测试和运行中只写可清理的系统临时 bare repository。

## UI acceptance scope

No browser UI is introduced. This module exposes Python/JSON read results only, so browser acceptance is not applicable.

## Architecture decisions

- 默认分支只由 `ls-remote --symref <remote-url> HEAD` 决定；禁止从本地 remote-tracking ref、当前分支或 `main`/`master` 候选猜测。
- 两阶段远端读取先记录 HEAD tip，再在临时 bare repository fetch；fetch 后 tip 改变即返回 `unknown`，不把第二个 tip 偷换成 review commit。
- baseline commit 与 review commit 分开：baseline 是 Proposal 的设计基准，必须是 review snapshot 默认分支历史的祖先；review map 是评审时的当前共享事实。
- Publication 只负责 remote Git provenance 与 snapshot；Proposal 文档语义交给 `proposal_contract.py`，能力图结构交给 `capability_map.py`，避免三套 parser 漂移。
- 结果对象复制必要文本与结构化事实，不返回临时文件路径；远端 URL 不进入诊断输出，避免泄漏凭据。

## Implementation slices

### Slice 1: Establish local bare-remote fixtures and result states

**Acceptance criteria:** Focused tests construct a remote with an explicit non-default-name HEAD and a separate dirty consumer checkout. They define `published`、`absent`、`invalid`、`unknown` outcomes without talking to external services.

**Verification:** The fixture proves its bare remote HEAD is actually set; a locally modified `spec/proposals/<id>.md` and map differ from, but cannot influence, the remote result.

**Likely files:** `plugins/spec-guard/hooks/test_proposal_publication.py`.

**Dependencies:** None.

### Slice 2: Implement bounded remote HEAD and snapshot acquisition

**Acceptance criteria:** A small subprocess wrapper uses argv arrays, timeouts and a temporary bare repository to resolve remote HEAD, fetch the observed ref and verify the fetched tip equals the observed commit. No fetch ref is written in the consumer repository.

**Verification:** Tests cover non-`main` HEAD, no remote/HEAD, Git command failure and a changed-tip fixture or runner stub; every ambiguous transport outcome is `unknown`.

**Likely files:** `plugins/spec-guard/hooks/proposal_publication.py`, focused tests.

**Dependencies:** Slice 1.

### Slice 3: Read and validate published Proposal provenance

**Acceptance criteria:** The reader extracts the exact remote Proposal path, baseline map and review map from immutable Git objects; requires baseline remote/default-branch equality and baseline-commit ancestry; then delegates static validation to `proposal_contract.py`.

**Verification:** Tests prove a valid remote Proposal is `published`, while missing Proposal is `absent`; malformed content, mismatched provenance, non-ancestor commit and invalid maps are `invalid`. No result carries a temporary pathname.

**Likely files:** `plugins/spec-guard/hooks/proposal_publication.py`, focused tests.

**Dependencies:** Slice 2 and `proposal-contract`.

### Slice 4: Expose stable read-only output and wire regressions

**Acceptance criteria:** A narrow Python/JSON entry point serializes state, review commit and safe diagnostics without dumping remote URLs or mutating the project. The focused test joins `scripts/validate.sh`; source guidance explains that publication does not query trackers.

**Verification:** `python3 -B plugins/spec-guard/hooks/test_proposal_publication.py`, `/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh`, `/bin/bash scripts/validate.sh` and `/bin/bash evals/codex-plugin-smoke.sh --selftest` pass.

**Likely files:** `plugins/spec-guard/hooks/proposal_publication.py`, `plugins/spec-guard/hooks/test_proposal_publication.py`, `plugins/spec-guard/references/proposal-publication.md`, `scripts/validate.sh`.

**Dependencies:** Slices 1–3.

### Checkpoint: Publication facts are safe to review

- The only `published` result comes from a single, proven remote-default snapshot and carries its review commit.
- A local worktree, cached remote-tracking ref, arbitrary reachable commit or moving remote cannot become a published fact.
- `absent`、`invalid` and `unknown` retain distinct meanings; no remote state or workflow artifact changes.
- Tracker reading, review status and capability-map promotion remain absent from this module.

## Dependency graph

```text
local bare-remote fixtures and states
                ↓
remote HEAD resolution and fixed snapshot
                ↓
baseline ancestry + contract/map validation
                ↓
safe JSON result and repository quality gate
```

The transport snapshot must precede all parsing; otherwise a later remote movement could mix Proposal and baseline inputs from different commits.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Local `origin/HEAD` is stale or absent | Never read it; resolve remote HEAD live through `ls-remote --symref`. |
| Default branch moves during publication | Compare fetched tip to the observed tip and return `unknown` on any mismatch. |
| Proposal baseline refers to a commit from another branch | Fetch the remote default branch history in isolation and require `merge-base --is-ancestor`. |
| Remote URL carries credentials | Keep it inside argv execution; diagnostics name only the configured remote alias. |
| Temporary Git data leaks into future evaluation | Use `TemporaryDirectory`, copy result data out and test cleanup/no project mutation. |
| Publication accretes tracker behavior | Keep dependencies limited to Git, `proposal_contract.py` and `capability_map.py`; tests reject API clients and bridge imports. |

## Current checkpoint

**Type:** implementation complete; awaiting review.

**Reviewable artifacts:** `spec/proposal-publication.md` and this plan.

**Completed:** A local bare-remote fixture proves that a fixed remote `trunk` snapshot yields `published`, ignores a different dirty consumer Proposal, reports an absent remote path as `absent`, rejects a mismatched baseline remote as `invalid`, and reports a changed remote tip as `unknown`. The implementation uses an isolated temporary bare repository, verifies fetched tip equality and checks baseline ancestry before delegating to `proposal_contract.py`. Safe JSON output and caller reference material are present; the focused regression is part of `scripts/validate.sh`.

**Next step:** Review the local diff. On explicit direction, begin `proposal-tracker-read` with a new module Spec; do not create or alter any Proposal Issue during that design step.

**Stop condition:** A request to cache remote content in the project, accept local facts, write tracker objects, alter the old bridge or loosen the fixed-snapshot rule requires an explicit new design decision.
