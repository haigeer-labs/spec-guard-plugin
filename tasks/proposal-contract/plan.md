# Plan: proposal-contract

Spec: `spec/proposal-contract.md`

## Overview

先建立 Candidate Proposal Pool 的最小、版本化事实契约：一个可严格解析的 Proposal 文档、一份可从固定远端默认分支 commit 复算的能力图基准、一个可精确匹配普通 Proposal Issue 的 marker，以及一个唯一的 tracker 阶段标签族。

此计划仅分解本模块的实现切片；它不创建 GitHub/GitLab Issue、任务、分支、PR、`.agent/state.json` 或任何远端对象。后续 `proposal-publication` 才取得远端发布事实，`proposal-tracker-read` 才读取 tracker。

## UI acceptance scope

No browser UI is introduced. This module produces a reference grammar and read-only command output only, so browser acceptance is not applicable.

## Architecture decisions

- Proposal 的共享输入有两层：文档声明的 immutable baseline 与以后 `proposal-publication` 固定的远端默认分支 commit；任何本地 worktree 都只能是草稿，不能参与事实选择。
- 所有 v1 文档都使用 `spec/proposals/<id>.md`、单一 marker 与单一 `new-module` change block，避免在首个模块引入“任意 Proposal”解析器。
- 能力图摘要只调用现有 `spec-digest.py`；Build order 作为显式字符串保留，因为该脚本的 `order` 是表格行序，不能偷换为构建顺序。
- Proposal Issue 仅以精确 marker、`proposal` 身份标签和单一阶段标签定义。标签变更不是本模块的写入职责，且不镜像进 `.agent/state.json`。
- 面向宿主的 intake/review 入口延后到 `proposal-boundary-guidance`，以免 contract 模块在没有远端事实或用户授权时暗中创建草稿、Issue 或任务。

## Implementation slices

### Slice 1: Write the public v1 grammar and examples

**Acceptance criteria:** Reference material defines the canonical path, id grammar, document sections, exact marker, full baseline fields, supported `new-module` fields and accepted tracker labels. It gives one valid minimal example and documents that fenced examples are non-semantic.

**Verification:** Focused fixture tests parse the valid example and reject altered marker, duplicate headings, unknown fields, malformed ids and unsupported change types.

**Likely files:** `plugins/spec-guard/references/proposal-contract.md`, `plugins/spec-guard/hooks/test_proposal_contract.py`.

**Dependencies:** None.

### Slice 2: Implement a narrow, read-only contract validator

**Acceptance criteria:** A standard-library helper parses only the documented grammar, returns `valid` or field-level `invalid` diagnostics, and has no function that writes local or remote state. It validates the marker, baseline table, module-digest coverage, change fields, dependency/anchor relationship and label-family cardinality from explicit inputs.

**Verification:** Unit tests cover valid zero- and multi-dependency proposals plus all static invalid cases; a filesystem/Git fixture confirms the validator leaves Proposal, map, state and refs untouched.

**Likely files:** `plugins/spec-guard/hooks/proposal_contract.py`, `plugins/spec-guard/hooks/test_proposal_contract.py`.

**Dependencies:** Slice 1.

### Slice 3: Bind declared baseline facts to the existing capability-map primitives

**Acceptance criteria:** The validator invokes `spec-digest.py` rather than reproducing a digest, checks caller-supplied `spec/CAPABILITY-MAP.md` bytes against the recorded goal/module digests and literal Build order, and has no Git-ref or worktree selection path. `proposal-publication` will later resolve the fixed remote-default commit and supply those bytes.

**Verification:** Markdown fixtures prove a matching map validates; a changed map, stale digest, missing module digest or different Build order cannot produce `valid`. Tests also show that the contract helper does not inspect Git state.

**Likely files:** `plugins/spec-guard/hooks/proposal_contract.py`, `plugins/spec-guard/hooks/test_proposal_contract.py`, potentially a minimal shared test fixture only.

**Dependencies:** Slice 2.

### Slice 4: Add repository-level regression coverage and discoverability

**Acceptance criteria:** Source tests use the contract's public result model; validation wiring and source documentation identify the new focused test without adding bridge coupling, tracker writes or a state projection.

**Verification:** `python3 -B plugins/spec-guard/hooks/test_proposal_contract.py`, `/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh`, `/bin/bash scripts/validate.sh`, and `/bin/bash evals/codex-plugin-smoke.sh --selftest` pass.

**Likely files:** `scripts/validate.sh`, `docs/maintainer-workflow.md` only if a new focused-test row is necessary, focused test files.

**Dependencies:** Slices 1–3.

### Checkpoint: Contract is safe to consume

- The full Proposal grammar is versioned, strictly parseable and has positive plus adversarial fixtures.
- No local dirty file, sibling worktree, remote tracker response or absent ref can be mistaken for a valid shared baseline.
- A Proposal Issue can later be located only by the complete marker and a single allowed stage label.
- No Issue, PR, branch, task, `.agent/state.json`, capability-map entry or remote object has been created or changed.

## Dependency graph

```text
public grammar/examples
        ↓
read-only parser and semantic validation
        ↓
fixed-commit capability-map verification
        ↓
regression wiring and repository validation
```

The slices are deliberately sequential: later modules consume this grammar and must not infer rules in parallel.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Markdown parser accepts a nearby example or partial marker | Parse only documented top-level sections, ignore fenced blocks and require full-line exact marker equality. |
| Build order is silently compared with the row order returned by `spec-digest.py` | Keep Build order as an independent literal baseline field and add a fixture where the two orders differ. |
| A later caller supplies a dirty checkout as a baseline | Keep Git/ref discovery out of this helper; `proposal-publication` must supply only a fixed remote-default commit and report unavailable provenance as `unknown`. |
| Tracker labels become a second mutable state store | Treat labels as read-only external facts; do not write them or mirror them in `.agent/state.json`. |
| Contract grows into the legacy bridge migration | Test imports/calls to keep `spec-github-bridge`, `/sync-map` and state-projection paths absent. |

## Current checkpoint

**Type:** implementation complete; awaiting review.

**Reviewable artifacts:** `spec/proposal-contract.md` and this plan.

**Completed:** The public v1 grammar, strict standard-library parser, caller-supplied capability-map validation, explicit tracker-fact validation and seven focused positive/negative regressions are implemented. The focused regression is part of `scripts/validate.sh`; no GitHub/GitLab object, task, branch, PR or `.agent/state.json` was created or modified.

**Next step:** Review the local diff. On explicit direction, begin `proposal-publication` from a new module Spec; do not infer publication facts from this checkout.

**Stop condition:** Any request to add a change type, accept local worktree facts, write tracker objects, or reuse the legacy bridge requires a new explicit design decision before implementation.
