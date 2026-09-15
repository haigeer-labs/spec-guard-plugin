# spec-guard design

## Purpose

spec-guard adds two independent safeguards around agent-skills:

1. A local multi-module file layout that prevents module plans and task lists
   from overwriting one another.
2. A Proposal lifecycle that reads a published remote-default-branch snapshot
   and explicit GitHub/GitLab Proposal Issue facts without side effects.

## Proposal boundary

Proposal is a six-module capability map.  It has no dependency on local state,
task selection, branch binding, or a mutable tracker.  The tracker adapters
are read-only and only recover a normal Proposal Issue by its full identity
marker in an explicitly supplied container.

## Local boundary

The optional local convention stores module documents under `spec/` and
`tasks/<module-id>/`.  Its state file can record a local active module, but is
not a Proposal pool and is never read by Proposal code.

## Retired boundary

The v0.14-era mutable remote tracker bridge is not part of the product.  It is
not hidden behind a compatibility route: remote projection, selection, binding,
delivery, and synchronization preview are absent.  Historical records remain
immutable evidence.  The full decision, migration rules, and acceptance
criteria live in [the retirement spec](retirements/spec-github-bridge-retirement.md).
