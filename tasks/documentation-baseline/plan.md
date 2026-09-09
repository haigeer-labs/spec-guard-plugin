# Plan: documentation-baseline

## Overview

实现文档治理的第一层：一个显式启用的项目级文档基线协议及其保守解析、预览式初始化入口。该模块不修改模块 Spec、Plan 或交付门槛；那些能力由后续模块完成。

## UI acceptance scope

No browser UI is introduced. This module produces Markdown and command output only, so browser acceptance is not applicable.

## Architecture decisions

- `docs/DOCUMENTATION-BASELINE.md` 是唯一新增治理索引；它只存引用、状态和理由，不复制原始文档内容。
- 解析采用小型标准库 Python helper；只接受明确、受限的 Markdown 结构，拒绝“猜测性解析”。
- 基线缺失代表项目未启用，不是违规；无效基线才输出可操作的诊断。
- 初始化先预览，确认后才写入；既有基线必须走显式更新路径。

## Task list

Tasks are local planning units while `workflowStage=local-validation` is active; no GitHub Issue index or `todo.md` is created.

### Task 1: Define and test the baseline grammar

**Acceptance criteria:** A documented minimal table format represents the three universal concerns, conditional concerns, authority locations, allowed statuses and reasons; `target` and `not-applicable` remain valid non-completion states.

**Verification:** Focused fixtures accept valid minimal and shared-source baselines; reject missing universal declarations, duplicate concerns, unknown statuses and unsupported empty rationales.

**Files likely touched:** `plugins/spec-guard/references/`, `plugins/spec-guard/hooks/`, focused parser test files.

### Task 2: Implement read-only baseline facts

**Acceptance criteria:** A standard-library helper returns distinct `absent`, `invalid` and `valid` facts without writing files or inspecting code diffs.

**Verification:** Unit tests cover local paths, external URLs, invalid structure and a no-mutation assertion over a temporary Git fixture.

**Files likely touched:** `plugins/spec-guard/hooks/`, focused Python tests.

**Dependencies:** Task 1.

### Task 3: Add explicit, preview-first host entry points

**Acceptance criteria:** Claude and Codex instructions can render a baseline proposal from user-provided facts; they do not create or overwrite the baseline before confirmation and preserve an existing project convention.

**Verification:** Host adapter and command-name tests cover preview, confirmed create, existing-file refusal and no-plugin/no-baseline behavior.

**Files likely touched:** `plugins/spec-guard/commands/`, `plugins/spec-guard/skills/spec-guard-ops/`, host adapter tests, README/template synchronization inputs.

**Dependencies:** Tasks 1–2.

### Checkpoint: Baseline protocol is reviewable

- The baseline remains an index rather than a duplicated requirement or architecture document.
- Unenabled projects receive no warning.
- No code heuristic can claim that a target-state architecture document is stale.
- Browser acceptance remains explicitly not applicable.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Markdown flexibility makes parsing ambiguous | Use a deliberately narrow, documented table grammar; invalid input is reported, never guessed. |
| The index becomes another copy of architecture content | Permit only references, status and short rationale; keep detail in the authority document. |
| Documentation governance becomes noisy | Require explicit opt-in and distinguish absent from invalid. |
| Users lose existing documentation conventions | Initialization references existing paths and refuses silent overwrite. |

## Current checkpoint

**Type:** approval

**Reviewable artifacts:** capability map, this module spec and this plan.

**Completed:** The baseline grammar, strict read-only parser, JSON query interface, Claude/Codex preview-first entry points and focused regressions are implemented. The parser distinguishes absent, valid and invalid input; target-state and not-applicable declarations remain explicit rather than inferred from code.

**Next step:** Review the local diff and complete the full repository validation. Then decide whether to commit this completed module or proceed to `documentation-impact`.

**Stop condition:** Tracker activation, task creation and remote writes remain out of scope. Any work on the next module requires its own Spec and Plan.
