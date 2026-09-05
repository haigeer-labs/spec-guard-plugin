# Plan: History Integrity Audit Remediation

> Tasks tracked in GitHub Issues #142

## Architecture

One Python history semantic interpreter reads existing ledger/checkpoint
artifacts and produces structured evidence findings. Correction is append-only:
it records sources and audit time without rewriting historic snapshots. Shell
and host instructions remain thin routes to that shared result.

## Task List

1. T1: Add read-only semantic audit for legacy guessed history fields.
2. T2: Add append-only evidence-backed correction event and schema validation.
3. T3: Align Claude/Codex routes, migration contract and focused regressions.
4. Checkpoint: Run history, host and full validation; record stub versus real
   tracker evidence limits.

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
