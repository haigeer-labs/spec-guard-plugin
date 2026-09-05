# Spec: Release Evidence and Host Acceptance

## Objective

Close F13 without overstating support: make Spec Guard's release claims
traceable to the correct kind of evidence. A developer must be able to tell
whether a capability is covered by source regression, packaged-content
inspection, fresh-install validation, a real host session, or a real tracker
project—and which cells remain unverified.

## Evidence Model

Every release-evidence entry uses exactly one of these statuses:

- `source-verified`: deterministic repository regression passed.
- `package-verified`: the distributable contains the expected files and
  manifest metadata.
- `installed-verified`: a newly installed version was loaded in a new host
  session and its declared entrypoint was observed.
- `host-verified`: an actual supported host exercised the stated behavior.
- `project-verified`: an explicitly approved GitHub or GitLab test project
  completed the documented journey.
- `not-verified` or `unsupported`: no weaker result may be presented as a
  stronger one.

Results apply to one named target only. GitHub does not prove GitLab; CLI does
not prove a desktop host; source regression does not prove an installed
package. Claude Desktop MCPB remains separate from Claude Code desktop mode.

## Required Behavior

- Provide a versioned release-evidence record and a deterministic validator
  that rejects invalid statuses, missing target identity, impossible evidence
  upgrades, and claims that a disabled parallel write path is available.
- Cover Codex CLI, Codex desktop, Claude Code CLI, Claude Code desktop mode,
  and Claude Desktop MCPB as distinct rows with their actual supported
  boundaries.
- Verify manifests/package contents and fresh-install instructions separately
  from source tests. The installed test must identify the version and session
  rather than infer it from the source checkout.
- Define reproducible, opt-in journeys for an approved GitHub test repository,
  an approved GitLab test repository, two manually created worktrees, and
  unavailable/offline/missing-plugin cases. External writes and real host
  actions require explicit user confirmation at execution time.
- Add release verification to the ordinary local gate, but make unavailable
  external environments produce `not-verified`, never a false success.
- Update release/user documentation and CHANGELOG only for capabilities with
  evidence at the claimed level. State that automatic parallel execution is
  not provided.

## Commands

```bash
/bin/bash scripts/validate.sh
/bin/bash evals/codex-plugin-smoke.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash plugins/spec-guard/hooks/test-claude-desktop-mcp.sh
```

The module may add a deterministic release-evidence validator and its focused
fixture test; both must be invoked by `scripts/validate.sh`.

## Project Structure

```text
docs/releases/                 human-readable release evidence records
evals/                         deterministic package/host evidence fixtures
plugins/spec-guard/            package manifests, skills, commands and hooks
scripts/validate.sh            ordinary local quality gate
```

## Testing Strategy

- Unit/fixture tests prove record schema, evidence-strength boundaries,
  manifest/package checks, and failure behavior.
- Existing Codex and Claude Desktop adapter tests remain required and prove
  their defined entrypoints only.
- Fresh-install and real-host tests record their exact target/version/session
  as evidence, or remain `not-verified`.
- Real GitHub/GitLab journeys are opt-in integration tests. They must record
  repository identity and expected side effects; a business repository is
  never assumed to be a disposable fixture.

## Boundaries

- Always: retain raw evidence references, run deterministic tests before
  recording `source-verified`, and disclose every unverified matrix cell.
- Ask first: publishing, tagging, installing/upgrading a user plugin, opening
  or merging external PRs/MRs, creating tracker data, or running a real-host
  / real-project journey.
- Never: fabricate host/project evidence, erase failed evidence, treat a
  successful command exit as task acceptance, claim automatic parallel
  execution, or weaken existing confirmation gates.

## Success Criteria

- An invalid or overclaimed evidence record fails a normal repository test.
- The published support matrix has an independently identifiable row for each
  host and evidence level.
- The release artifact's contents and version are mechanically checked.
- A fresh-install procedure either records its actual observation or clearly
  reports `not-verified`.
- Real-project and real-host evidence cannot be claimed without their target
  identity and explicit execution record.
- Full local validation passes without needing network access or a desktop
  session.

## Explicit Non-Goals

This module does not publish a release, tag a version, create an automatic
parallel executor, or convert unverified environments into supported ones.
