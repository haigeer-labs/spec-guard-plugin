# Proposal publication

Publication reads one Proposal only from an explicit Git remote's current default branch. It uses a temporary bare snapshot and returns JSON; it never reads a local Proposal or capability map as shared fact, and it never calls a tracker API.

```bash
python3 -B plugins/spec-guard/hooks/proposal_publication.py \
  --project . --proposal-id example-proposal --remote origin
```

The response contains `state` and, when known, `reviewCommit`. A `published` result also names `proposalId` and `baselineCommit`. It deliberately omits remote URLs, temporary paths and document/map contents.

- `published`: the fixed remote-default snapshot and Proposal contract both validate.
- `absent`: the Proposal path is not on that snapshot.
- `invalid`: a found Proposal or its provenance is invalid.
- `unknown`: remote observation could not safely complete; this is not a successful remote verification.

Publication does not read GitHub/GitLab Issues. Tracker marker and stage validation belongs to `proposal-tracker-read`.
