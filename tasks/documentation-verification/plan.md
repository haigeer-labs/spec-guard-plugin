# Plan: documentation-verification

## Overview

为已启用基线且已记录模块影响的项目增加交付前只读核验。它以保守提醒呈现声明性文档结果，默认不阻止实现、Issue 或 PR 工作流。

## UI acceptance scope

No browser UI is introduced. This module produces Markdown and command output only, so browser acceptance is not applicable.

## Architecture decisions

- `Documentation outcome` 是 Plan 内的人工声明，不新建 state 或证据账本。
- 结果分为 `ready`、`attention`、`absent`、`invalid`；其中只有无效结构是解析错误，attention 只是不能伪装为完成的提醒。
- verify-artifacts 只消费当前活跃模块的事实，不在每次 prompt 扫描所有模块。
- `delivered` 的证据是指针而非自动验真；后续可另设内容审核，不在本模块偷换概念。

## Task list

Tasks are local planning units while `workflowStage=local-validation` is active; no GitHub Issue index or `todo.md` is created.

### Task 1: Define outcome grammar and read-only facts

**Acceptance criteria:** A focused helper distinguishes absent, invalid, attention and ready; it requires result/evidence/rationale only according to declared outcome semantics.

**Verification:** Unit tests cover pending decisions, omitted outcome, delivered evidence, deferred reason, unknown values and fenced examples.

**Files likely touched:** `plugins/spec-guard/hooks/`, `plugins/spec-guard/references/`, focused Python tests.

### Task 2: Surface non-blocking verification

**Acceptance criteria:** verify-artifacts prints module document facts as pass/attention/invalid without treating attention as a failure; absence remains quiet.

**Verification:** Fixture tests assert output and exit behavior for every result state.

**Files likely touched:** `plugins/spec-guard/hooks/`, verifier tests.

**Dependencies:** Task 1.

### Task 3: Add cross-host preview guidance

**Acceptance criteria:** Claude and Codex operations query the same helper and require confirmation before modifying outcomes or authority documents.

**Verification:** Host adapter and command-name regressions pass.

**Files likely touched:** `plugins/spec-guard/commands/`, `plugins/spec-guard/skills/spec-guard-ops/`, adapter tests.

**Dependencies:** Tasks 1–2.

### Checkpoint: Delivery status remains honest

- `attention` never becomes a hard gate.
- `ready` is explicitly limited to declared-document status.
- No output infers content quality, implementation conformity or external publication.
- Browser acceptance remains explicitly not applicable.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Self-reported delivery is mistaken for proof | Use “declared” wording and require only evidence pointers, not inferred validation. |
| Repeated reminders become noise | Show them only in explicit artifact verification and only for the active module. |
| A reminder accidentally blocks delivery | Keep attention outside verify-artifacts failure accounting. |
| Outcome table duplicates plan content | It records final disposition, while delivery table records intent; each has one purpose. |

## Current checkpoint

**Type:** approval

**Reviewable artifacts:** this module spec and plan.

**Completed:** The outcome grammar, strict read-only verification helper, JSON query interface, non-blocking verify-artifacts reminder, Claude/Codex entry points and focused regressions are implemented. `ready` remains explicitly limited to declared delivery status; missing, pending and deferred items remain attention.

**Next step:** Review the local diff, complete full repository validation, and decide whether to commit the Documentation Governance initiative.

**Stop condition:** Tracker activation, task creation, remote writes and automatic business-document updates remain out of scope.
