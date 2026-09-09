# Plan: workflow-roadmap

## Overview

Implement an on-demand, read-only workflow roadmap after the completed `workflow-checkpoint-preview` module.
The capability map remains the only module/dependency source, upstream `agent-skills` remains the lifecycle and
task-format authority, and existing Spec Guard state remains contextual evidence. No tracker write, state mutation,
runtime management, percentage or ETA is in scope.

## UI acceptance scope

No browser UI is introduced. This module produces command/hook text only, so browser acceptance is not applicable.

## Architecture decisions

- Add one deterministic, standard-library Python roadmap helper that returns structured facts and a renderer-ready
  model. It calls existing strict parsers/classifiers rather than reparsing human hook output.
- Keep automatic `phase-guard.sh` offline and compact. Its only roadmap-related addition is Git execution context
  that can be established locally and cheaply.
- Use one host-neutral output contract. Claude command instructions and Codex `spec-guard-ops` delegate to the
  same helper; neither host owns a separate lifecycle interpretation.
- Treat tracker data as an optional read-only overlay. An unavailable tracker preserves local output and yields
  unknown remote facts.
- Keep the completed `workflow-checkpoint-preview` plan untouched. This is a new module, dependent on it.

## Dependency graph

```text
strict capability-map parser + state + Git + phase classifier
                         ↓
                roadmap fact collector/model
                         ↓
          roadmap renderer / Claude and Codex entry points
                         ↓
      compact phase context and focused regression coverage
```

## Task list

Tasks are local planning units while `workflowStage=local-validation` is active; no GitHub Issue index or
`todo.md` is created.

### Task 1: Build the read-only roadmap fact model

**Description:** Add a small hook helper that identifies the active Initiative from state plus map, parses only the
active map’s module graph, obtains Git worktree/HEAD facts, and exposes evidence-bearing values without writing.

**Acceptance criteria:**

- Reject ambiguous/unreadable active Initiative or map rather than choosing by file recency or module count.
- Distinguish primary versus linked worktree and attached branch versus detached HEAD.
- Expose lifecycle position, plugin mode, task facts and Git context as separate fields.
- Return explicit unknown/inconsistency facts and never calculate a percentage, ETA or inferred total.

**Verification:** Focused unit tests cover a valid map, missing state/map, ambiguous identity, linked worktree,
detached HEAD and dirty worktree. Mutation of state, map and Git metadata is asserted absent.

**Files likely touched:**

- `plugins/spec-guard/hooks/workflow-roadmap.py`
- `plugins/spec-guard/hooks/test_workflow_roadmap.py`
- existing strict parser/classifier imports only if a minimal shared API is required

**Dependencies:** None.

### Task 2: Render the route, checkpoints and completion gaps

**Description:** Turn the fact model into the fixed roadmap structure: normal upstream route, current graph
location, next action versus execution permission, nearest declared checkpoint, completion conditions, evidence
legend and risks. Add `--all` expansion without treating table order as dependencies.

**Acceptance criteria:**

- Default output shows the current module and direct graph neighbours; `--all` lists only active-map modules.
- Structured checkpoints are shown faithfully; unstructured/missing checkpoints remain unknown.
- `local-validation` suppresses remote recommendations.
- Task file scope is displayed only when declared by the active task source; it is labelled estimated scope.

**Verification:** Unit fixtures cover linear and branching maps, missing checkpoint/task facts, tracker-unavailable
state, local-validation and a completed-looking zero-task source that must not become completion.

**Files likely touched:**

- `plugins/spec-guard/hooks/workflow-roadmap.py`
- `plugins/spec-guard/hooks/test_workflow_roadmap.py`

**Dependencies:** Task 1.

### Checkpoint: Roadmap facts are reviewable

- [ ] The renderer exposes no second state machine or persisted roadmap state.
- [ ] Unknown/ambiguous fixtures produce `?`/`!`, not optimistic progress.
- [ ] The output identifies the fact source for current Initiative, module, checkpoint and Git context.

### Task 3: Add Claude and Codex on-demand entry points

**Description:** Add the user-visible roadmap command and the equivalent Codex operation. Both call the shared
read-only helper and state that tracker reads are optional, explicit and non-mutating.

**Acceptance criteria:**

- User-visible command names exist in both supported host paths and pass command-name validation.
- The command does not request or perform tracker writes, binding, task claiming, state updates or runtime control.
- Codex adapter coverage proves the new operation is registered once and retains the shared path-resolution rules.

**Verification:** Run the command-name checker and Codex adapter suite, including a fixture with unavailable remote
facts that still returns a local roadmap.

**Files likely touched:**

- `plugins/spec-guard/commands/roadmap.md`
- `plugins/spec-guard/skills/spec-guard-ops/SKILL.md`
- `plugins/spec-guard/hooks/test-codex-adapter.sh`
- generated Codex command-skill source, if the repository’s packaging convention requires one

**Dependencies:** Tasks 1–2.

### Task 4: Keep automatic phase output compact and document the contract

**Description:** Extend the existing compact phase facts with verified worktree/HEAD context, then document the
roadmap’s evidence and non-goals without changing existing task or tracker authority.

**Acceptance criteria:**

- `/phase` identifies a linked worktree and detached HEAD without printing the full roadmap or making network calls.
- Existing local-validation suggestion remains local-only.
- Documentation explains that worktree/branch/port isolation is execution context, not module binding or progress.

**Verification:** Add focused positive and negative phase-guard assertions; run the documented test suites and
inspect `git diff --check`.

**Files likely touched:**

- `plugins/spec-guard/hooks/phase-guard.sh`
- `plugins/spec-guard/hooks/test-phase-guard.sh`
- `README.md` or `docs/design.md`

**Dependencies:** Tasks 1–3.

### Checkpoint: Implementation-ready roadmap contract

- [ ] All commands, data sources and no-write boundaries are represented in tests.
- [ ] `--all`, local-validation, tracker-unavailable, ambiguous Initiative and detached worktree cases are covered.
- [ ] The plan still contains no task checklist competing with a future activated tracker.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| A friendly summary drifts from the real phase classifier | Extract/reuse a narrow shared classifier contract; never parse human hook prose. |
| Git facts are mistaken for module/task authority | Render execution context separately and test that it never grants permission. |
| Tracker outage produces fake completion | Make remote reads optional and represent failures as unknown. |
| Full roadmap inflates every turn’s context | Keep it behind the explicit command; hook only emits compact local facts. |
| Capability-map ordering is mistaken for a dependency graph | Use only strict parser dependency edges and label absent edges unknown. |

## Current checkpoint

**ID:** workflow-roadmap/spec-and-plan

**Type:** approval

**Recorded:** 2026-09-09

**Reviewable artifacts:** the roadmap helper, its focused regression suite, Claude/Codex entry points, compact
phase worktree facts, and the accompanying Spec/Plan/README changes.

**Completed:** The user confirmed the V1 boundary. Tasks 1–4 are implemented: a read-only fact model and renderer,
`--all` expansion, conservative tracker overlay, Claude/Codex entry points, compact primary/linked/detached Git
facts, focused negative tests, command-name validation and Codex adapter regression all pass. The full
`/bin/bash scripts/validate.sh` suite completed with exit 0. Browser acceptance is not applicable because this
module has no web surface.

**Next step:** Review the final local diff and decide whether to commit or release.

No tracker or release operation is queued.

**Stop condition:** Implementation scope is complete. Any commit, installation, tracker activation or release needs
separate authorization.
