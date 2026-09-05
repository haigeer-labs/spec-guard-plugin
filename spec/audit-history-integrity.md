# Spec: History Integrity Audit Remediation

## Objective

Repair F11: capability-history must not present guessed responsibility,
dependencies, lifecycle status or timestamps as historical facts. Preserve
existing checkpoint files and ledger events; add an explainable audit and an
explicit, append-only correction path.

## Evidence model

1. A checkpointed capability map is the sole source for module responsibility
   and `dependsOn` at that checkpoint.
2. A checkpointed state file and recorded tracker Issue may support identity,
   but neither proves task or module completion by itself.
3. Git commit metadata and merged tracker evidence may support a completion
   claim only when they identify the same module/Issue.
4. Any field without admissible evidence is `unknown`; it must never be
   inferred from the current `activeModule`, a filename, or the current clock.

## Required behavior

- Add a read-only history semantic audit that reports legacy guessed fields,
  missing evidence and contradictions without modifying the ledger.
- Add an explicit migration command that creates an append-only correction
  event with sources, before/after values and an audit timestamp. It may not
  rewrite a historic checkpoint or fabricate source timestamps.
- Extend schema validation and focused fixtures for responsibility/dependency
  fidelity, status/time evidence and legacy compatibility.
- Claude and Codex routes expose the same read-only audit and migration
  boundary. GitHub Issues remain the sole task truth.

## Boundaries

- Always preserve existing artifacts and fail closed on malformed or ambiguous
  evidence.
- Ask first before any non-dry-run correction or migration write.
- Never delete/rewrite checkpoint evidence, convert unknown to completed,
  introduce a new task store, or claim historical truth from a checksum alone.

## Verification

```bash
/bin/bash plugins/spec-guard/hooks/test-capability-history.sh
/bin/bash plugins/spec-guard/hooks/test-history-migration.sh
/bin/bash plugins/spec-guard/hooks/test-history-verification.sh
/bin/bash scripts/validate.sh
```
