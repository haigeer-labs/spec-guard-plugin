# Plan: proposal-boundary-guidance

Spec: `spec/proposal-boundary-guidance.md`

## Architecture decisions

- Guidance is a pure function over an explicit boundary token. It does not inspect a worktree, `.agent/state.json`, pending tasks, Issue data or prior workflow output.
- Only `module-deliver` and `module-advance` can return a reminder. The result is informational: neither a proposal nor an approved action is inferred.
- Entry ids document the completed Proposal modules in lifecycle order; they do not invoke them, query remotes or mutate a tracker.
- This plan intentionally has no tracker task list: the user forbids automatically creating or changing tasks/Issues, and existing tracker machinery is outside the new capability boundary.

## Implementation slices

### Slice 1: Boundary matrix fixtures

Add red/green in-memory tests for the two reminder boundaries, non-boundary suppression and invalid input. Verify that no subprocess or filesystem access is necessary.

### Slice 2: Pure guidance result and safe serialization

Implement the smallest result model, fixed lifecycle entry ordering and safe JSON. Keep all result text independent of Proposal/Issue/map contents.

### Slice 3: Caller reference and quality gate

Document the three entry paths, remote-default provenance and non-blocking semantics. Wire the focused suite into `scripts/validate.sh` and run full validation.

## Dependency graph

```text
explicit boundary matrix
          ↓
pure reminder/result model
          ↓
reference guidance + full validation
```

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Reminder becomes an implicit approval | Use an informational state and document that it never performs or authorizes an action. |
| Guidance reintroduces local candidate state | Accept only an explicit boundary token; do not list, save or discover candidates. |
| Old bridge leaks into entry guidance | Reference only completed Proposal modules; test that no subprocess or bridge import exists. |
| Reminders appear during ordinary work | Return `not-applicable` outside the two defined boundaries. |

## Current checkpoint

**Type:** implementation complete; focused-test and repository full validation passed.

**Next step:** All modules in this capability map are implemented. Review the local diff before any separately authorized integration, migration or commit.
