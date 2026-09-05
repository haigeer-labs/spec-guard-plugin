# Plan: Release Evidence and Host Acceptance

> Tasks tracked in GitHub Issues #143

## Architecture

A small, deterministic evidence validator is the shared foundation. It
validates versioned records without network access and never upgrades evidence
strength. Package inspection consumes a named artifact rather than the source
tree; host, installation and real-project runs only append identifiable
observations through documented, confirmation-gated journeys.

## Task List

- [#190 — T1: Define and validate release evidence records](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/190)
- [#191 — T2: Verify release manifests and packaged content](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/191) (blocked by #190)
- [#192 — T3: Publish a host support and installation evidence matrix](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/192) (blocked by #190)
- [#193 — T4: Add opt-in real-project and degraded-environment journeys](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/193) (blocked by #190)
- [#194 — Checkpoint: Deliver release evidence acceptance](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/194) (blocked by #191, #192, #193)

## Verification

```bash
/bin/bash scripts/validate.sh
/bin/bash evals/codex-plugin-smoke.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash plugins/spec-guard/hooks/test-claude-desktop-mcp.sh
```

## Risks and Boundaries

No local fixture proves an installed plugin, a desktop host, GitHub, or GitLab.
Those rows remain `not-verified` unless an explicitly approved, named target
and observation are recorded. This module does not publish, tag, merge, create
external tracker data, or enable automatic parallel execution.
