# Plan: History Integrity Audit Remediation

> Tasks tracked in GitHub Issues #142

## Architecture

One Python history semantic interpreter reads existing ledger/checkpoint
artifacts and produces structured evidence findings. Correction is append-only:
it records sources and audit time without rewriting historic snapshots. Shell
and host instructions remain thin routes to that shared result.

## Task List

- [#185 — T1: Add a read-only semantic audit](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/185)
- [#186 — T2: Add an append-only correction path](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/186)
- [#187 — T3: Align Codex and Claude history-integrity routes](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/187)
- [#188 — Checkpoint: Review and deliver history integrity remediation](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/188)

## Verification

```bash
/bin/bash plugins/spec-guard/hooks/test-capability-history.sh
/bin/bash plugins/spec-guard/hooks/test-history-migration.sh
/bin/bash plugins/spec-guard/hooks/test-history-verification.sh
/bin/bash scripts/validate.sh
```

## Boundaries

No checkpoint rewrite, no automatic correction, no guessed source timestamp,
and no second task truth source. Non-dry-run corrections require user approval.
