# Implementation Plan: Tracker Integrity Audit Remediation

## Overview

Implement the approved F06–F08 repair in one module branch. The work first
creates deterministic identity/recovery primitives, then wires safe GitLab
sync, per-worktree context binding and GitLab task selection into the existing
host routes. GitHub Issues are the only task truth; this document records
architecture, order and issue IDs rather than a second checklist.

> Tasks tracked in GitHub Issues #141

## Architecture Decisions

1. **One deterministic implementation, thin host routes.** Python owns marker,
   state, binding and selection interpretation; shell/Markdown only pass
   arguments and render structured results. This prevents Claude, Codex and
   GitLab paths from independently reimplementing the same identity rule.
2. **Digest marker beats title matching.** A GitLab Issue is recoverable only
   through the complete v2 marker plus the expected project/kind/digest. Search
   merely finds candidates; it never decides identity.
3. **Per-worktree Git metadata, not a new shared state model.** Bindings live
   under the current `git rev-parse --git-dir`, so normal file checkout and
   `activeModule` remain backward-compatible. A binding is local context, not
   a tracker task source, global lease or active-module array.
4. **Fail closed on uncertain context.** Missing, copied, malformed or stale
   binding; unreadable Git data; unclear pagination; or tracker API failure
   stops write-capable `next`/`deliver` before a task is selected or changed.
5. **GitLab plan order remains a fallback order only.** The selector validates
   the module/task marker and remote state, skips current-branch completed
   tasks, and does not reinterpret `relates_to` as a dependency edge.

## Dependency Graph

```text
strict map digest + tracker response validation (T1)
       ├── GitLab sync recovery and atomic state projection (T2)
       └── worktree-local binding contract (T3)
              ├── host entry-point and diagnostic parity (T4)
              └── deterministic GitLab next selector (T5)
                         └── documentation and regression integration (T6)
                                      └── delivery checkpoint (T7)
```

The tasks deliberately remain serial: T2 and T3 share the new identity
contract; T4/T5 consume the binding format; T6 must document observed rather
than assumed behavior. This is an audit repair, not a candidate for parallel
module execution.

## Task List

### Phase 1: Identity and recovery foundation

GitHub sub-issues created from the approved task payloads are recorded below.
This section remains an ordered index, not a duplicate checklist.

- #175 T1: 建立严格 GitLab 投影身份基元
- #176 T2: 使 GitLab 能力图同步可恢复且原子化（blocked by #175）

### Checkpoint A: Recovery foundation

The GitLab map parser/recovery tests and existing strict-map regressions pass;
the only accepted outcomes for ambiguous remote state are a diagnostic and no
remote/local projection mutation.

- #177 Checkpoint A: 审查恢复行为（blocked by #176）

### Phase 2: Worktree context and task selection

The corresponding GitHub sub-issues are recorded below.

- #178 T3: 增加显式 worktree 本地 tracker 绑定（blocked by #177）
- #179 T4: 入口与诊断统一执行绑定门禁（blocked by #178）
- #180 T5: 实现 GitLab next 的确定性选择对齐（blocked by #179）

### Checkpoint B: Context safety

A copied or unbound worktree cannot reach tracker selection/delivery; an open
GitLab task with a local closing commit cannot be selected again.

- #181 Checkpoint B: 审查上下文与选择安全（blocked by #180）

### Phase 3: Contract integration and delivery

The corresponding GitHub sub-issues are recorded below.

- #182 T6: 对齐公开契约与常规验证覆盖（blocked by #181）

### Checkpoint C: Module delivery review

Run focused and full validation, inspect each host route against the shared
checker, and prepare the module-level PR only after all task evidence is
complete.

- #183 Checkpoint C: 模块交付评审（blocked by #182）

## Approved Task Payloads

The following payloads are source material for the GitHub sub-issues. After
creation, the issue bodies are canonical; do not maintain these as a live task
checklist.

### T1 — Establish strict GitLab projection identity primitives

**Acceptance criteria**

- Implement a shared Python interface that builds/parses v2 initiative and
  module markers from `spec-digest.py` values and validates structured Issue
  responses, repository identity and exact marker equality.
- Distinguish zero, one and multiple candidate matches; malformed JSON,
  incomplete result pages and marker mismatch fail closed.
- Add focused tests and a mutation/selftest proving title-only or partial
  marker matching is rejected.

**Verification**

```bash
/bin/bash plugins/spec-guard/hooks/test-gitlab-tracker-integrity.sh
/bin/bash plugins/spec-guard/hooks/test-sync-map-gitlab.sh
```

**Dependencies:** None.  
**Likely files:** shared Python helper, focused test, existing GitLab sync test.  
**Scope:** M.

### T2 — Make GitLab capability-map sync recoverable and atomic

**Acceptance criteria**

- Refactor `sync-map-gitlab.sh` to use T1's strict capability-map and recovery
  interface, verify existing/recovered objects before writing state, and make
  supported state updates atomic.
- Repeat sync produces no additional Issue creation; a simulated lost create
  response recovers the unique remote object; stale/foreign/ambiguous state
  produces no compensating POST or mapping overwrite.
- `goalDigest`/`rowDigest` match the shared digest program and `activeModule`
  changes only after all module mappings verify.

**Verification**

```bash
/bin/bash plugins/spec-guard/hooks/test-sync-map-gitlab.sh
/bin/bash plugins/spec-guard/hooks/test-gitlab-tracker-integrity.sh
```

**Dependencies:** T1.  
**Likely files:** sync wrapper, shared helper, focused sync tests, GitLab bridge contract.  
**Scope:** M.

### Checkpoint A — Review recovery behavior

**Acceptance criteria**

- Review the exact marker, pagination and atomic-write behavior against the
  spec, including all no-write failure paths.
- Run the focused suite plus map-consistency regression; record evidence.

**Verification**

```bash
/bin/bash plugins/spec-guard/hooks/test-gitlab-tracker-integrity.sh --selftest
/bin/bash plugins/spec-guard/hooks/test-sync-map-gitlab.sh
/bin/bash plugins/spec-guard/hooks/test-audit-map-consistency.sh
```

**Dependencies:** T2.  
**Likely files:** verification record and focused tests only.  
**Scope:** S.

### T3 — Add explicit worktree-local tracker context binding

**Acceptance criteria**

- Implement the local binding record and a deterministic inspect/bind API using
  the current worktree's Git directory, canonical remote, tracker, initiative,
  module and optional task Issue identity.
- Reject copied records, wrong Git directory/remote/tracker/module mappings,
  invalid JSON, non-Git directories and unresolved predecessor modules before
  any selection/write action.
- Provide an explicit migration/bind command; do not auto-enrol unbound
  worktrees in `/next` and do not change `activeModule` to an array.

**Verification**

```bash
/bin/bash plugins/spec-guard/hooks/test-gitlab-tracker-integrity.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
```

**Dependencies:** T1.  
**Likely files:** binding helper, focused test, bind command contract.  
**Scope:** M.

### T4 — Enforce the shared binding across host entry points and diagnostics

**Acceptance criteria**

- Claude commands, Codex ops routes and GitHub/GitLab bridge guidance invoke
  the same context result before write-capable next/deliver behavior.
- `phase-guard` and `verify-artifacts` expose missing/mismatched binding as a
  read-only actionable diagnostic without creating, repairing or replacing it.
- Legacy ordinary serial projects receive the explicit migration direction,
  not a false claim of concurrent safety.

**Verification**

```bash
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
```

**Dependencies:** T3.  
**Likely files:** commands, both bridge/ops skills, phase/verify hooks and tests.  
**Scope:** M.

### T5 — Implement deterministic GitLab next selection parity

**Acceptance criteria**

- Select only valid, bound, plan-indexed, marker-matched and remotely opened
  GitLab task Issues in plan order.
- Exclude another user's assignment and all task IIDs already closed by commits
  between the resolved default base and `HEAD`; return a valid unfinished local
  task binding rather than selecting a second task.
- Never use `relates_to` as a dependency/lease, never fall back to GitHub, and
  fail closed on unreadable remote/API facts.

**Verification**

```bash
/bin/bash plugins/spec-guard/hooks/test-gitlab-tracker-integrity.sh
/bin/bash plugins/spec-guard/hooks/test-gitlab-bridge.sh
```

**Dependencies:** T3, T4.  
**Likely files:** GitLab selector/helper, GitLab bridge skill, focused tests.  
**Scope:** M.

### Checkpoint B — Review context and selection safety

**Acceptance criteria**

- Run the two-worktree fixtures, marker/assignment/closing-keyword cases and
  host-route parity tests; record a no-write result for every invalid context.
- Confirm no test or route claims cross-machine lease semantics.

**Verification**

```bash
/bin/bash plugins/spec-guard/hooks/test-gitlab-tracker-integrity.sh --selftest
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
```

**Dependencies:** T5.  
**Likely files:** verification record and focused tests only.  
**Scope:** S.

### T6 — Align public contracts and normal validation coverage

**Acceptance criteria**

- Update README, GitLab/Codex/Claude guidance and CHANGELOG so they state the
  exact recovery/binding behavior and remaining non-lease/non-parallel limits.
- Add the focused suite to the ordinary validation gate without weakening
  existing map, history, GitHub or parallel-write-containment tests.
- Document the actual GitLab-instance query as pending final real-project
  evidence rather than claiming stub tests prove E2E support.

**Verification**

```bash
/bin/bash scripts/validate.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
```

**Dependencies:** T2, T4, T5.  
**Likely files:** docs, validation script, smoke/contract tests.  
**Scope:** M.

### Checkpoint C — Module delivery review

**Acceptance criteria**

- Execute the defined test matrix, perform the five-axis review and write a
  verification report distinguishing stub evidence from real GitLab E2E.
- Verify no untracked proposal is staged, no new task source exists and the PR
  contains `Closes #141` plus every completed sub-issue in its commit history.

**Verification**

```bash
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
```

**Dependencies:** T6.  
**Likely files:** verification report and final test evidence.  
**Scope:** S.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| GitLab 15.3 search/pagination differs from current docs | Duplicate recovery could be incomplete | Capability-check and test against the designated instance before making E2E claims; ambiguity/unreadable pages stop. |
| Binding blocks upgraded serial projects | Users cannot use `/next` immediately | Provide a one-time explicit bind command and clear phase diagnostic; do not silently enroll. |
| Binding is mistaken for a distributed lock | Concurrent same-task work remains possible | Document the boundary, do not make lock claims, and leave controller/lease work outside this module. |
| Markdown and executable routes drift | One host bypasses the gate | One structured checker plus contract tests for every route. |
| Digest migration changes old mappings | False drift or overwritten history | Reuse `spec-digest.py`, preserve valid records and reject incompatible ones. |

## Open Questions / Evidence Gates

1. The designated GitLab instance must be queried read-only during
   implementation to confirm exact marker search and pagination semantics.
   If it differs, the implementation must use its supported endpoint or keep
   recovery disabled rather than guessing.
2. Real Issue/MR write-side testing remains a final release-evidence task and
   requires the existing explicit target/side-effect confirmation.
3. No task here creates a global lease or claims same-module concurrency is
   safe. A future executor proposal must not be folded into this repair.
