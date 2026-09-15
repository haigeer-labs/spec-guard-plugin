# Implementation Plan: Retire the legacy tracker bridge

## Overview

This plan removes the old mutable GitHub/GitLab orchestration in small,
verifiable slices.  It intentionally does not change the six-module Proposal
capability map or create tracker work items.

## Dependency order

```
retirement contract + negative regression
    -> public command/skill removal
        -> mutable helper and adapter removal
            -> hook and setup simplification
                -> documentation, release notes, full validation
```

## Tasks

### 1. Establish the retirement contract and negative regression

**Acceptance criteria:** A focused test distinguishes active, distributed
surfaces from preserved historical evidence and fails while any retired public
entry point remains.

**Verification:** Run the focused regression before and after the first code
slice; it must fail before removal and pass after.

### 2. Remove public bridge entry points

**Acceptance criteria:** Both bridge skills and the four public orchestration
commands are absent from the distributed plugin.  No template or adapter
advertises them.

**Verification:** The focused regression and command/manifest checks pass.

### 3. Remove mutable tracker implementations and routing

**Acceptance criteria:** GitLab sync/write/selection/binding helpers, desktop
sync preview, and hook tracker routing are gone.  Proposal read-only adapters
remain present and do not import the removed helpers.

**Verification:** Proposal focused suites and the retirement regression pass
without a tracker CLI or network access.

### 4. Simplify setup, validation, and documentation

**Acceptance criteria:** Setup exposes no GitHub/GitLab tracker modes; phase,
verification, and validation no longer expect tracker projection state; README
and maintainer docs describe the breaking migration and preserved history.

**Verification:** Updated focused regressions pass and no active documentation
contains a removed callable path.

### 5. Release readiness

**Acceptance criteria:** Manifests use a consistent breaking-release version,
CHANGELOG documents removal and migration, and release evidence names the
exact verification scope.

**Verification:** `git diff --check`, all focused suites, and
`/bin/bash scripts/validate.sh` pass.  No remote write or release action is
performed without separate user authorization.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| A stray legacy reference survives in an adapter or template | Assert the shipped surface by path and content, with an explicit allowlist for immutable history. |
| Proposal silently reuses old code | Run all six Proposal focused tests after tracker helper removal. |
| Removing old state checks breaks unrelated history utilities | Preserve non-tracker history code and test it separately. |
| Docs retain an executable migration instruction | Treat active docs as part of the negative regression; preserve only explicitly historical sources. |

## Checkpoints

- After Tasks 1–3: no callable bridge code remains; focused retirement and
  Proposal suites pass.
- After Tasks 4–5: full repository validation passes and the working tree is
  ready for review.
