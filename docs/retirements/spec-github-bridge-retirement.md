# Spec: Retire the legacy tracker bridge

## Objective

Remove the legacy mutable GitHub/GitLab tracker orchestration from spec-guard
without changing the published Proposal lifecycle.  The retired surface includes
the tracker projection, task selection, worktree binding, and remote delivery
paths that formerly used `spec-github-bridge`, `spec-gitlab-bridge`, or
`/sync-map`.

Proposal remains a separate, read-only lifecycle: its shared facts come only
from the remote default branch; GitHub and GitLab remain read-only Proposal
Issue sources; and it must neither read nor write `.agent/state.json`.

## Scope

### Remove

- Public skills `spec-github-bridge` and `spec-gitlab-bridge`.
- Commands `/spec-guard:sync-map`, `/spec-guard:next`,
  `/spec-guard:deliver`, and `/spec-guard:bind-workspace`.
- Mutable remote tracker implementations, including GitLab sync, task
  selection, remote bridge, and workspace-binding helpers.
- Tracker projection / routing behaviour in phase and artifact verification,
  desktop sync previews, templates, setup instructions, tests, and public
  documentation.

### Preserve

- Proposal hooks, references, tests, and their GitHub/GitLab **read-only**
  adapters.
- Local multi-module directory conventions and the non-tracker documentation
  and history facilities, unless a call site exists solely to support the
  retired bridge.
- Existing users' `.agent/state.json`, Issue/PR/MR records, archived maps,
  release evidence, changelog entries, research, and `spec/history/` as opaque
  historical data.  No migration step deletes, rewrites, or synchronizes them.

## Compatibility and migration

This is a breaking removal in the next release after v0.14.0.

- The release contains no compatibility command or remote fallback.  A removed
  command or skill must not remain discoverable or callable.
- A local, read-only legacy-state diagnostic may explain that a repository was
  previously tracker-managed.  It performs no authentication, network request,
  `.agent/state.json` mutation, or task selection, and expires in the following
  minor release.
- Users with active GitHub or GitLab work must complete, abandon, or manually
  preserve it with v0.14.0 before upgrading.  The migration guide describes
  this as a user decision; the plugin performs no external write.
- New users use Proposal's explicit read-only entry points.  A future mutable
  tracker product needs a new approved design and must not reuse this bridge.

## Design constraints

- Do not add a retirement module under `spec/`: phase and artifact verification
  interpret every `spec/*.md` file as a member of the live Proposal capability
  map.  Retirement records live in `docs/retirements/`.
- Never invoke `/sync-map` or use `.agent/state.json` to complete the current
  Proposal work.
- Retained Proposal code must not import or invoke removed bridge helpers.
- Hook output stays valid host JSON and silently ignores unconfigured projects.
- No change in this migration may create or modify an Issue, PR, MR, branch,
  task, remote ref, or user repository state.

## Success criteria

1. Distributed plugin contents contain no callable legacy bridge skill,
   command, mutable tracker helper, or desktop sync-preview operation.
2. GitHub/GitLab tracker projection, task selection, worktree binding, and
   remote write behaviour are absent rather than hidden behind a fallback.
3. Historical evidence remains available, while active documentation has one
   clear breaking-change migration path.
4. Proposal focused suites prove no bridge, `/sync-map`, or state-pool
   dependency and preserve read-only behaviour.
5. A dedicated retirement regression proves the shipped surface has no retired
   entry point; `scripts/validate.sh` passes in full.

## Boundaries

- Always: run focused regressions for each removal slice and retain released
  history verbatim.
- Ask first: any remote write, new external tracker integration, or change to
  Proposal's published contract.
- Never: restore a mutable tracker compatibility shim, mutate legacy state, or
  treat a local worktree as Proposal shared fact.
