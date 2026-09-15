# Proposal review

Review combines an already `published` remote-default Publication with an already
`verified` read-only Proposal Issue. It never queries or changes GitHub, GitLab,
Git, the capability map, Proposal files or `.agent/state.json`.

`accepted` is an observed Issue label, not promotion authorization. `promoted-claim`
is also only an observed label; run a fresh review before the later Promotion-proof
module. `stale` means the remote review map already contains the proposed module or
the Proposal baseline/anchor facts have drifted.

`as_json(review_result)` returns only safe identifiers, state/stage and stable
diagnostic codes. It omits map text, Issue body/comments, markers, URLs, tokens,
temporary paths and raw errors.
