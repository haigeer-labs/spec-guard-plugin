# Spec: Archive GitHub Repository Identity

## Objective

An archived GitHub initiative currently records only its Epic number
(`initiative.issue`). `phase-guard.sh` later resolves the repository from the
*current* origin (`github_repository_from_origin`) and queries
`gh issue view N --repo <current>`. After a repository transfer, remote change or
deletion, this either fails ("unverified") or silently checks the wrong Epic.

Record the repository identity at archive time inside the fingerprinted state
snapshot, and verify archived Epics only against that recorded repository.

## Data contract

- New optional field in `.agent/state.json` snapshots:
  `initiative.repository`, a string `owner/repo` matching
  `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`, case preserved (the `gh --repo` form).
  No host is stored: SSH aliases such as `github-haigeer` are not real hosts.
- Written only when `tracker` is `github`. Other trackers are untouched.
- The live `.agent/state.json` is not modified by archiving; only the snapshot
  under `.agent/history/<initiative>/<checkpoint>/state.json` gains the field.

## Required behavior

### Write (`hooks/initiative-lifecycle.sh`)

1. After copying the state snapshot and **before** computing its sha256, if
   `tracker == "github"`:
   - If the state already carries a valid `initiative.repository` (e.g. it was
     restored by `resume` from an earlier checkpoint), keep it unchanged. The
     Epic lives where it was first recorded, even if origin has since changed.
   - Otherwise resolve `owner/repo` from `git remote get-url origin` using the
     current accepted URL forms (`scheme://host/owner/repo[.git]`,
     `user@host:owner/repo[.git]`, host containing `github`) and write it into
     the snapshot.
2. If resolution fails (no origin, non-GitHub host, unrecognized URL), archive
   still succeeds without the field and prints one notice that this checkpoint
   cannot be remotely verified later.
3. The ledger `state.sha256` is computed from the final snapshot bytes, so
   `capability-history.py verify` and `verify-history.sh` stay green.
4. `resume` keeps copying the snapshot verbatim, so a restored state carries the
   recorded repository into the next archive (rule 1).

### Verify (`hooks/phase-guard.sh`, archived GitHub loop)

1. Read `initiative.repository` from the archived snapshot together with the
   tracker and Epic number.
2. With remote verification opted in and a valid recorded repository, query
   `gh issue view N --repo <recorded>`. OPEN / CLOSED / MERGED handling is
   unchanged. Report the Epic as `owner/repo#N`.
3. Missing or invalid repository: never call `gh`, never fall back to origin;
   report `GitHub Epic #N（缺少仓库身份）` as unverified.
4. `github_repository_from_origin` has no remaining caller in `phase-guard.sh`
   and is removed from it; the URL parsing moves to the lifecycle script.

### Visible consequence (accepted)

Existing GitHub archives lack the field. They are reported as
"未核验（缺少仓库身份）" whether or not remote verification is opted in (the
identity check precedes the opt-in check); with opt-in they previously verified
via the current origin. Old checkpoints and ledger events are never rewritten to
hide this. Improving the follow-up hint for such archives is tracked in #20.

## Boundaries

- Always: preserve old checkpoint bytes and ledger events; keep `phase-guard.sh`
  dependent only on `bash`, `git`, `python3`; keep remote verification opt-in.
- Ask first: extending the same design to GitLab; any correction or migration
  that writes repository identity into existing history.
- Never: guess the repository from the current origin during verification;
  fail an archive because repository identity is unavailable; change digest
  algorithms or `spec-digest.py`.

## Testing strategy

Shell regression suites with the existing PATH-stubbed `gh`, no network.

- `test-initiative-lifecycle.sh`
  - GitHub origin (SSH alias and https) → snapshot has `initiative.repository`,
    ledger sha256 matches the snapshot file.
  - No origin → archive succeeds, no field, notice printed.
  - `tracker: none` → no field.
  - State already carrying `repository` with a different origin → recorded value
    kept.
- `test-phase-guard.sh` (archived GitHub fixture)
  - Recorded `old/repo` while origin is `new/repo` → `gh` is called with
    `--repo old/repo` only; CLOSED → verified, OPEN → drift.
  - Missing repository → unverified with "缺少仓库身份", zero `gh` calls.
  - Invalid repository string → unverified, zero `gh` calls.
  - Existing opt-in, no-`gh` and missing-snapshot cases keep passing.
- `test-history-verification.sh` stays green (digest of augmented snapshot).

## Commands

```bash
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-initiative-lifecycle.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash plugins/spec-guard/hooks/test-history-verification.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
```

## Documentation

- `skills/spec-github-bridge/SKILL.md` state field list: add
  `initiative.repository` (written by lifecycle archive, not by agents).
- `CHANGELOG.md`: note the new field and the verification behavior change.

## Success criteria

- Every new GitHub archive with a resolvable origin stores `owner/repo`, and its
  ledger digest verifies.
- Archived verification never queries a repository other than the recorded one.
- Absent or invalid identity yields "unverified" with no `gh` call.
- No existing file under `spec/history`, `tasks/history` or `.agent/history`
  changes.
- All commands above pass.

## Open questions

None blocking. GitLab parity is explicitly deferred.
