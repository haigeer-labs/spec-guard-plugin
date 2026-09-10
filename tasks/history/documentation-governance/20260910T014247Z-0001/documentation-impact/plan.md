# Plan: documentation-impact

## Overview

在已完成的文档基线之上，建立模块级“文档影响 → 计划交付物”的显式、只读事实链。默认只提示或报告不完整决定，不阻塞编码或替代用户对业务文档的判断。

## UI acceptance scope

No browser UI is introduced. This module produces Markdown and command output only, so browser acceptance is not applicable.

## Architecture decisions

- 模块 Spec 的 `Documentation impact` 表是决定层；Plan 的 `Documentation delivery` 表只承接 `update`/`create` 的预期交付物，二者不混写为文档真实性。
- 基线不存在时静默返回 `absent`；基线无效或决策表无效时报告具体结构错误，不猜测缺失项。
- 所有适用基线关注点必须获得模块级决定；项目级 `not-applicable` 关注点不进入模块覆盖要求。
- 默认模式仅输出事实和提醒。后续模块才决定如何把未收口项呈现到 verify/deliver。

## Task list

Tasks are local planning units while `workflowStage=local-validation` is active; no GitHub Issue index or `todo.md` is created.

### Task 1: Define impact and delivery grammars

**Acceptance criteria:** A reference defines decision values, Spec table and Plan delivery table, including why project-level and module-level not-applicable are distinct.

**Verification:** Focused parser tests accept complete, pending and no-impact cases; reject duplicate rows, unsupported values and empty rationales.

**Files likely touched:** `plugins/spec-guard/references/`, `plugins/spec-guard/hooks/`, focused Python tests.

### Task 2: Implement read-only impact facts

**Acceptance criteria:** A standard-library helper composes the baseline with module Spec and Plan, distinguishes absent/invalid/valid states, and reports required decisions and planned delivery without inspecting code or Git.

**Verification:** Unit tests cover absent baseline, missing coverage, update/create delivery coupling, fenced examples and no-mutation behavior.

**Files likely touched:** `plugins/spec-guard/hooks/`, focused Python tests.

**Dependencies:** Task 1.

### Task 3: Add preview-first host guidance

**Acceptance criteria:** Claude and Codex entry points explain the facts and can draft tables from user-provided decisions, but require confirmation before changing a module Spec or Plan.

**Verification:** Host adapter checks assert the new operation uses the helper and states the confirmation/no-code-inference boundaries.

**Files likely touched:** `plugins/spec-guard/commands/`, `plugins/spec-guard/skills/spec-guard-ops/`, host adapter tests.

**Dependencies:** Tasks 1–2.

### Checkpoint: Impact decisions are reviewable

- A module cannot silently treat applicable upstream documentation as considered.
- `update` and `create` have planned delivery records; `pending` remains visible.
- No parser result claims that a document was updated or that code conforms to it.
- Browser acceptance remains explicitly not applicable.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Requiring every document for every module creates noise | Require decisions only for applicable baseline entries; module-level `not-applicable` remains explicit. |
| Plan entries get mistaken for publishing evidence | Name the table `Documentation delivery` and limit it to planned output; later verification owns evidence. |
| The parser over-interprets Markdown | Use one narrow table per section and reject ambiguity. |
| Reminders turn into accidental release gates | Keep this module read-only; do not attach it to a blocking hook. |

## Current checkpoint

**Type:** approval

**Reviewable artifacts:** this module spec and plan.

**Completed:** The impact and delivery grammars, strict read-only parser, JSON query interface, Claude/Codex preview-first entry points and focused regressions are implemented. Applicable baseline concerns require explicit module decisions; `update` must plan the same baseline authority, while `create` may name a new planned artifact.

**Next step:** Review the local diff and complete full repository validation. Then decide whether to commit this completed module or proceed to `documentation-verification`.

**Stop condition:** Tracker activation, task creation and remote writes remain out of scope. Delivery verification is reserved for `documentation-verification`.
