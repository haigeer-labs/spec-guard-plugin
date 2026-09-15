# Plan: proposal-promotion-proof

Spec: `spec/proposal-promotion-proof.md`

## Architecture decisions

- Proof is a fresh remote-default observation, not a label transition or local diff.
- It requires an `accepted` review and verifies first appearance on the default branch's first-parent history against the promotion commit's first parent.
- Existing Proposal, publication, review and capability-map validators remain authoritative; no bridge/state client is imported.

## Implementation slices

### Slice 1: Remote-history fixtures and proof states

Add local bare-remote fixtures for proved, non-accepted, invalid and unknown without external services.

### Slice 2: Fixed snapshot and first-appearance verification

Reuse isolated remote snapshot mechanics; verify parent absence and exact map/Proposal relationship.

### Slice 3: Safe output and quality gate

Add JSON/reference guidance, focused test wiring and full validation.

## Current checkpoint

**Type:** implementation complete; merge-history focused test and repository full validation passed.

**Next step:** All modules in this capability map are implemented. Review the local diff before any separately authorized integration, migration or commit.
