# Plan: Parallel Order Conflict Guard

> Tasks tracked in GitHub Issues #86

## Task List

### Phase 1: Regression

- #87 Add regression for explicit serial build-order conflict

### Phase 2: Conservative classification

- #88 Classify serial build-order conflicts as needs-review (blocked by #87)

## Verification

1. Run `plugins/spec-guard/hooks/test-parallel-safety-gate.sh`.
2. Run `scripts/validate.sh` before delivery.
