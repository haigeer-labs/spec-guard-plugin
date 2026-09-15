# Plan: proposal-tracker-read

Spec: `spec/proposal-tracker-read.md`

## Overview

实现一个小型、fixture-first 的 GitHub/GitLab Proposal Issue 读取器：输入是已解析 Proposal 和显式平台容器，输出是安全的 `verified`、`absent`、`invalid` 或 `unknown`。它只恢复并核验 tracker 阶段事实；不参与 Proposal 发布、综合评审、能力图晋级或旧 bridge 迁移。

本计划不创建 Issue、tracker task、PR、分支或 `.agent/state.json`。该仓库现有 tracker 约定虽将任务事实源指向 Issues，但本 initiative 的用户约束禁止自动创建或修改它们，因此本文件是唯一计划记录。

## UI acceptance scope

No browser UI is introduced. This module exposes Python/JSON read results only, so browser acceptance is not applicable.

## Architecture decisions

- 平台和容器是必填显式输入；不从 git remote 或结果中的标题、URL、编号猜测范围。
- 搜索只是候选发现；身份恢复统一以正文 `splitlines()` 中的完整 Proposal marker 为准，并要求完整分页和唯一匹配。
- `proposal_contract.validate_tracker` 保持 marker/标签的唯一权威；adapter 只做平台 payload 正规化、范围/完整性证明和状态映射。
- GitHub/GitLab transport 分别最小化为只读 argv 调用，并由可注入 runner 测试；不导入旧 bridge client 或 state writer。
- 缺认证、CLI 失败、网络失败、响应缺字段或分页不完整均是 `unknown`；已获完整且矛盾的事实才是 `invalid`。

## Implementation slices

### Slice 1: Define cross-platform fixture contract and failure matrix

**Acceptance criteria:** Focused tests use a parsed Proposal fixture and independent GitHub/GitLab payload fixtures to define all four result states. Tests make title-only/partial marker, duplicate marker, foreign container and incomplete pagination observable failures.

**Verification:** `python3 -B plugins/spec-guard/hooks/test_proposal_tracker_read.py` fails before the adapter exists, without network or tracker mutation.

**Likely files:** `plugins/spec-guard/hooks/test_proposal_tracker_read.py`.

**Dependencies:** `proposal-contract`.

### Slice 2: Build pure candidate recovery and contract delegation

**Acceptance criteria:** A small pure layer validates normalized response fields, requires exact body-line marker and target-container equality, rejects legacy bridge markers, and delegates labels to `proposal_contract.validate_tracker`.

**Verification:** Fixture tests prove `verified` is impossible without one complete marker match and exactly the contract-approved labels; all ambiguities retain their distinct `invalid`/`unknown` result.

**Likely files:** `plugins/spec-guard/hooks/proposal_tracker_read.py`, focused tests.

**Dependencies:** Slice 1.

### Slice 3: Add bounded GitHub and GitLab read transports

**Acceptance criteria:** Platform adapters use only read/auth/search/list commands, explicitly collect all candidate pages, and normalize ordinary Issue body/label/container fields. Runner failures, malformed responses and incomplete collection are `unknown`.

**Verification:** Stubbed argv assertions reject mutation verbs and old bridge imports; fixtures cover both platforms, pagination and malformed payloads without live credentials.

**Likely files:** `plugins/spec-guard/hooks/proposal_tracker_read.py`, focused tests.

**Dependencies:** Slice 2.

### Slice 4: Stabilize safe JSON output and repository guidance

**Acceptance criteria:** A narrow Python/JSON entry point reports safe platform/container/Issue/stage data without body, comment, token or API URL leakage. Focused tests join the repository validation script; reference guidance explains that this is read-only and not a review or promotion action.

**Verification:** `python3 -B plugins/spec-guard/hooks/test_proposal_tracker_read.py`, `/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh`, `/bin/bash scripts/validate.sh` and `/bin/bash evals/codex-plugin-smoke.sh --selftest` pass.

**Likely files:** `plugins/spec-guard/hooks/proposal_tracker_read.py`, `plugins/spec-guard/hooks/test_proposal_tracker_read.py`, `plugins/spec-guard/references/proposal-tracker-read.md`, `scripts/validate.sh`.

**Dependencies:** Slices 1–3.

### Checkpoint: Tracker facts are safe to review

- A `verified` result comes only from an explicit platform/container, complete search and one exact body marker with valid Proposal labels.
- An incomplete page, unavailable CLI/service or unparseable response cannot become `absent` or `verified`.
- No tracker object, local state, Git ref or bridge state changes during either normal or failure paths.
- Publication provenance, review aggregation and promotion remain outside the adapter.

## Dependency graph

```text
fixture contract and failure matrix
                ↓
pure exact-marker recovery + label delegation
                ↓
GitHub/GitLab bounded read transports
                ↓
safe JSON output + repository quality gate
```

Transport is deliberately after pure recovery: platform-specific pagination must prove it supplies a complete candidate set before that set can acquire identity semantics.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| A search API treats marker text as fuzzy | Treat every result as a candidate and recheck the complete marker line in the Issue body. |
| A first page hides a second identical marker | Require platform pagination completion; otherwise return `unknown`. |
| A wrong repository/project leaks into results | Require explicit container identity and reject any exact match outside it. |
| CLI/API failures look like no Issue | Map unavailable or malformed transport to `unknown`, never `absent`. |
| New reader grows old bridge side effects | Keep imports/argv tests narrow and prohibit bridge/state clients. |
| Diagnostic output leaks secrets or discussions | Serialize only minimal identifiers, stage and sanitized diagnostic codes. |

## Current checkpoint

**Type:** implementation complete; awaiting review.

**Reviewable artifacts:** `spec/proposal-tracker-read.md`, this plan, `plugins/spec-guard/hooks/proposal_tracker_read.py`, `plugins/spec-guard/hooks/test_proposal_tracker_read.py`, `plugins/spec-guard/references/proposal-tracker-read.md` and `scripts/validate.sh`.

**Completed:** The focused fixture contract defines one verified GitHub/GitLab Issue and the `absent`、`invalid`、`unknown` failure matrix. A pure recovery layer requires explicit platform/container, a complete candidate set, a visible full marker and uniqueness; it delegates label validation to `proposal_contract.validate_tracker` and rejects legacy bridge markers. Bounded transports use only `gh api search/issues?...` and `glab api projects/<id>/issues?...` GET argv calls; GitHub proves collection using a stable `total_count` and `repository.full_name`, while GitLab explicitly includes all Issue states and reads through a short page. CLI, JSON, response-shape or pagination uncertainty remains `unknown`. Safe JSON exposes only platform, target, verified Issue/stage facts or a stable diagnostic code. Review findings also added an early proposal-id grammar check before any Git transport. Caller guidance is present, and the focused tests are part of `scripts/validate.sh`; the full validator passes.

**Next step:** Review the local diff. On explicit direction, begin `proposal-review` with a new module Spec; do not create, modify or migrate any Proposal Issue during that design step.

**Stop condition:** A request to infer tracker scope, use partial results, cache state locally, mutate a tracker object, include comments as facts, or connect the old bridge requires an explicit new design decision.
