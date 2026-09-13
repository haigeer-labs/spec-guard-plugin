# Plan: Archive GitHub Repository Identity

> Tasks tracked in GitHub Issues #16

Spec: `spec/archive-github-repository.md`

## Architecture

The write side and the read side meet at one field in the fingerprinted state
snapshot: `initiative.repository` (`owner/repo`).

- **Write:** `initiative-lifecycle.sh` already copies `.agent/state.json` into
  `.agent/history/<initiative>/<checkpoint>/state.json` and hashes the copy.
  Between the copy (:183) and the hash (:185), a Python step adds the recorded
  repository for `tracker: github`. The URL parsing moves here from
  `phase-guard.sh`, keeping its accepted forms and its "host contains `github`"
  rule.
- **Read:** `archived_completed_trackers` in `phase-guard.sh` emits the
  recorded repository as a fourth field. The archived GitHub loop queries only
  that repository and no longer calls `github_repository_from_origin`, which is
  then deleted.

Nothing else reads archived tracker identity (`verify-artifacts`, the history
verifiers and the MCP tools only touch digests or current state), so no other
routes change.

## Task List

- #17 T1: Record GitHub repository identity in archive snapshots
- #18 T2: Verify archived GitHub Epics only against the recorded repository（blocked by #17）
- #19 Checkpoint: End-to-end verification before delivery（blocked by #18）

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Rewriting the snapshot through `json.dump` changes formatting versus the live state | Low | The hash is taken after the rewrite. `resume` copies the rewritten file back; add a pause→resume→complete test confirming the field survives. |
| The GitHub host rule now exists in Python (lifecycle) as well as Bash (phase-guard/verify-artifacts) | Med | Mirror the "host contains `github`" rule exactly and cover SSH alias, https and a non-GitHub host in T1 tests. |
| Existing archives turn "unverified" when opt-in is set | Accepted | Called out in the spec and CHANGELOG. No rewrite of history. |
| Hooks in this repo run installed v0.9.0, not source | Med | Judge only by the source test suites and the temporary consumer project, never by this repo's injected hook output. |

## Boundaries

GitHub only, no GitLab parity, no history rewrite or correction event, remote
verification stays opt-in, no new task truth source.
