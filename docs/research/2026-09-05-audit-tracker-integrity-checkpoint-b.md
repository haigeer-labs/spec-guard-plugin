# Tracker Integrity Checkpoint B

Date: 2026-09-05

## Verified safety boundary

The worktree binding is local context only. It is not a cross-worktree or
cross-machine lease, and it does not create agents, worktrees, branches,
Issues, merge requests, or parallel execution.

The focused fixtures use two real temporary Git worktrees and prove that a
copied binding, wrong repository/tracker/module mapping, malformed record,
foreign assignee, missing exact task marker, and unresolved predecessor all
stop without selecting another task. An unfinished local `taskIssue` is
returned unchanged. A task is selected only from the plan index, in order,
after exact marker, opened-state, assignee and current-branch closing-keyword
checks.

## Evidence

```text
/bin/bash plugins/spec-guard/hooks/test-gitlab-tracker-integrity.sh --selftest  # 13
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh                           # 131 / 0
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh                       # 73 / 0
```

## Remaining limit

These checks use controlled local Git and `glab` stubs. They do not claim a
real write E2E against the supported GitLab instance; that remains a final
release-evidence activity with an explicitly chosen remote target.
