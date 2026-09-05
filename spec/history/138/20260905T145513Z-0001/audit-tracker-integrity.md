# Spec: Tracker Integrity Audit Remediation

## Objective

Repair the tracker-facing parts of Spec Guard that can duplicate GitLab Issues,
silently replace a known mapping, or let a copied worktree select an unrelated
task. This module closes audit findings F06–F08 while keeping the product a
workflow-consistency plugin: it does not become a controller, a task database,
or an automatic parallel executor.

The intended outcome is conservative and explainable:

1. A repeated GitLab capability-map sync either reuses exactly the recorded or
   marker-recovered Issue, creates only a missing Issue, or stops on ambiguity.
2. A write-capable `next` or `deliver` call has an explicit local worktree
   binding to one initiative and module before it may select or deliver work.
3. GitLab task selection does not reselect an open Issue whose closing commit
   already exists on the current module branch.

This is a reliability repair, not evidence that two agents may concurrently
write the same module or that GitLab supplies native task dependencies.

## Tech Stack

- Bash entry points in `plugins/spec-guard/hooks/` and Markdown command/skill
  contracts.
- Python 3 standard library for strict JSON, Git, plan-index and binding
  validation.
- Git CLI for repository root, per-worktree Git directory, default-base and
  `Closes #<iid>` evidence.
- `glab` and the GitLab REST Issues API for authenticated tracker reads/writes.
- The existing `capability-map.py` and `spec-digest.py` are the sole parsers of
  capability-map structure and projection digests.

The recovery query is based on GitLab's documented project Issues listing:
`GET /projects/:id/issues` supports `search`, which searches title and
description. The implementation must locally verify the full marker and must
not treat a text-search result as an identity match by itself.

Sources:

- https://docs.gitlab.com/api/issues/#list-all-project-issues
- https://docs.gitlab.com/api/search/#search-a-project
- https://docs.gitlab.com/api/issues/#create-an-issue

## Project Structure

| Path | Responsibility |
| --- | --- |
| `plugins/spec-guard/hooks/gitlab-tracker.py` | Shared deterministic parser/validator for GitLab map recovery and task selection. |
| `plugins/spec-guard/hooks/workspace-binding.py` | Creates and validates per-worktree local bindings; never writes tracker state. |
| `plugins/spec-guard/hooks/sync-map-gitlab.sh` | Thin authenticated wrapper around the shared GitLab sync operation. |
| `plugins/spec-guard/hooks/test-gitlab-tracker-integrity.sh` | Focused regression and mutation tests with a controlled `glab` stub. |
| `plugins/spec-guard/commands/{next,deliver,sync-map,bind-workspace}.md` | Claude command contracts that invoke the shared checks. |
| `plugins/spec-guard/skills/{spec-gitlab-bridge,spec-guard-ops}/SKILL.md` | GitLab and Codex route contracts, aligned with the same check. |
| `plugins/spec-guard/hooks/{phase-guard,verify-artifacts}.sh` | Read-only diagnostics for missing, stale or mismatched bindings. |
| `README.md` and `docs/claude-desktop.md` | User-facing limits, migration and four-host wording. |

Exact filenames may be adjusted during planning, but the implementation must
have one shared deterministic context validator; the same check must not be
copied independently into Claude, Codex, GitLab and shell prose.

## Data Contracts

### GitLab projection marker

Every newly created projection Issue includes an exact, machine-readable HTML
comment. Its identity is derived from the capability-map digest, not from an
Issue title:

```text
<!-- spec-guard-sync:v2 kind=initiative goalDigest=<12-hex> -->
<!-- spec-guard-sync:v2 kind=module id=<module-id> rowDigest=<12-hex> -->
```

- The initiative marker uses `goalDigest` from `spec-digest.py`.
- A module marker uses the matching `rowDigest`, module id and the initiative
  IID in ordinary human-readable text outside the marker.
- Recovery accepts a remote Issue only when its complete marker, repository
  identity and expected kind all match. A matching title is never sufficient.
- Zero matches means the object is absent; one match can be recovered; two or
  more matches is an ambiguity error. The script must not choose one or create
  another Issue.

The existing supported fields remain the projection record:

```json
{
  "initiative": { "issue": 17, "goalDigest": "abc123def456" },
  "modules": {
    "billing": { "issue": 18, "rowDigest": "0123456789ab" }
  }
}
```

No array of active modules, tracker cache, duplicate task list or execution
ledger is introduced. State writes use a temporary file plus atomic rename and
occur only after a remote create or recovery has been verified.

### Per-worktree binding

The binding is a local, non-versioned record beneath the current worktree's
own Git directory (from `git rev-parse --git-dir`), never in the working tree,
common Git directory or `.agent/state.json`.

```json
{
  "version": 1,
  "gitDir": "/absolute/per-worktree/git-dir",
  "repo": "canonical origin identity",
  "tracker": "github|gitlab",
  "initiativeIssue": 17,
  "moduleId": "billing",
  "moduleIssue": 18,
  "taskIssue": null
}
```

`bind-workspace` explicitly creates or replaces this record only after showing
the module and tracker identity. `next` writes `taskIssue` only after it has
selected that exact task; it returns the existing unfinished binding rather
than silently selecting another task. A closing commit permits advancing the
local task binding.

The binding module may differ from `state.activeModule` only in an explicitly
bound linked worktree. `activeModule` remains the single canonical default for
ordinary serial flow; it is not converted to an array. This permits two
user-owned worktrees to carry distinct, dependency-eligible module bindings
without claiming global task locking.

An absent binding, a copied binding whose `gitDir` differs, inconsistent
tracker/repository/initiative/module Issue, detached or unreadable Git facts,
or an unresolved dependency is `context-unknown`: all write-capable
`next`/`deliver` routes stop before selecting, assigning, creating or merging.

## Required Behavior

### A. GitLab map synchronization and recovery

1. Strictly parse the map and compute its digest before any remote mutation.
2. Inspect `state.json` and classify the request as recover, supplement or
   explicit refresh. A changed digest never silently rewrites Issue content.
3. For each projected object, validate its recorded IID if present. If absent
   (including a lost POST response), query by the unique marker and locally
   apply the exact-match rule above.
4. Create only an object with no recorded or recovered match. Immediately
   re-read the created object, verify its marker/IID, then atomically record
   the supported issue and digest fields.
5. Preserve all previously valid mappings. A stale, foreign, deleted or
   ambiguous mapping produces an actionable error and no compensating POST.
6. Set `activeModule` only after every module mapping has been verified.

The implementation must paginate recovery results or fail closed when it
cannot prove the complete result set was inspected. It must not rely on the
current GitLab documentation alone: the actual supported GitLab instance is a
separate acceptance target.

### B. Shared context gate

The following entry points must invoke the same validator before write-capable
work begins: Claude `/next` and `/deliver`; Codex `spec-guard-ops` next and
deliver paths; GitHub/GitLab bridge guidance; and deterministic GitLab task
selection. `phase` and `verify-artifacts` report a read-only diagnostic using
the same record format.

The validator checks, in order:

1. a Git repository and current worktree-local Git directory;
2. binding syntax and its Git-directory identity;
3. canonical origin / tracker identity and the recorded initiative/module;
4. `state.json` mapping and capability-map membership;
5. predecessor completion where a non-default bound module is selected;
6. task binding versus closing-commit evidence.

It returns structured JSON with a stable code (`ok`, `context-unknown`,
`context-mismatch`, `task-in-progress`, or `dependency-blocked`) plus a
human-readable remediation. Markdown consumers must render that result rather
than reinterpret it.

### C. GitLab `/next` parity for local completion

Given a valid GitLab worktree binding, select only an Issue that is:

- listed in the active module's plan index and marked with that module's
  machine marker;
- remotely `opened`;
- not assigned to another account;
- not already referenced by a `Closes #<iid>`-style closing keyword between
  the resolved default base and current `HEAD`; and
- not superseded by an unfinished local `taskIssue` binding.

Order remains the plan order. GitLab `relates_to` is displayed only as a
non-authoritative association; it is not used as dependency or readiness
evidence. The selector does not pretend that assignees are a lease and does
not add an automatic remote claim.

## Commands

Focused tests introduced by this module must run without a real account:

```bash
/bin/bash plugins/spec-guard/hooks/test-gitlab-tracker-integrity.sh
/bin/bash plugins/spec-guard/hooks/test-sync-map-gitlab.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
```

The normal repository gate remains:

```bash
/bin/bash scripts/validate.sh
```

The final release-evidence module, not this one, performs the confirmed
write-side journey against the designated GitLab test project and records the
instance/version result separately from stub tests.

## Code Style

Keep side-effecting shell wrappers small and route data interpretation through
one Python module. Use explicit structured results rather than parsing prose:

```python
def reject(code: str, message: str) -> dict[str, object]:
    return {"ok": False, "code": code, "message": message}

binding = load_binding(git_dir)
if binding["gitDir"] != str(git_dir.resolve()):
    return reject("context-mismatch", "binding belongs to another worktree")
```

No `eval`, no fallback from `glab` to `gh`, no title-only recovery, no
best-effort selection after an API failure, and no unstructured stderr treated
as successful JSON.

## Testing Strategy

Tests must prove both the intended behavior and the safety failures:

| Area | Required examples |
| --- | --- |
| Sync idempotence | First sync creates N objects; repeat creates zero; state/IIDs/digests stay unchanged. |
| Interrupted sync | Lost response after each create recovers one exact marker; pre-existing mapping is never overwritten. |
| Ambiguity | Two exact markers, marker mismatch, deleted IID, bad JSON, pagination uncertainty and API failure all stop without POST. |
| Binding | Fresh bind passes; copied record, different Git directory, wrong remote, wrong module Issue, missing record and malformed JSON fail closed. |
| Selection | Closed task is skipped; a branch-closing commit skips an open task; unfinished local binding is returned; foreign assignee is skipped; an actually open eligible task is selected. |
| Entry-point parity | Claude and Codex docs invoke the shared checker; phase/verify report invalid binding without writing it. |
| Regression | Existing GitHub and ordinary unbound legacy serial migration paths retain an explicit, documented migration route. |

The focused suite is added to `scripts/validate.sh`. It includes a selftest or
mutation check that demonstrates at least: removing exact marker validation,
removing the Git-directory comparison, or removing the local closing-commit
filter makes the suite fail.

## Boundaries

### Always

- Strictly validate capability maps and structured tracker responses.
- Keep remote writes opt-in and show their targets before execution.
- Preserve old mapping and old worktree records on every error.
- Keep GitLab, GitHub and local tracker paths explicitly separated.

### Ask First

- Creating GitLab Issues or Merge Requests in a real project.
- Rebinding an existing worktree to another module.
- Refreshing an existing remote projection whose digest has changed.
- Closing non-new GitLab Issues or deleting any branch/worktree.

### Never

- Convert `activeModule` into an array or introduce a global executor ledger.
- Claim cross-worktree or cross-machine mutual exclusion from a local binding.
- Auto-create agents, worktrees, tracker tasks, branches, MRs or merges.
- Use `relates_to`, labels, a title prefix, or an assignee as a replacement for
  a dependency edge or a lease.
- Silently repair an ambiguous or foreign tracker record.

## Success Criteria

1. F06–F08 have a direct implementation, focused regression evidence and
   clearly scoped remaining limitations.
2. A repeated or interrupted GitLab sync cannot create a duplicate projection
   when a unique exact marker can be recovered; ambiguity produces no write.
3. A copied or unbound worktree cannot select/deliver a tracker task.
4. GitLab `/next` does not reselect a locally completed, still-open task.
5. Ordinary single-worktree migration has an explicit one-time binding path.
6. Existing GitHub behavior, strict map parsing and no-auto-parallel policy
   remain covered by the normal validation gate.
7. README, commands and both host routes make the same support claim.

## Open Questions

1. Does the designated GitLab 15.3 instance return complete marker search
   results through the documented endpoint with this account and pagination
   behavior? The implementation will capability-check it and the final module
   will record a real-project result; until then it is not claimed as E2E
   proof.
2. The exact migration UX (`/spec-guard:bind-workspace` command name and
   whether it accepts an explicit module argument) will be chosen in the plan,
   but it must remain an explicit local action rather than automatic enrollment
   in `/next`.
