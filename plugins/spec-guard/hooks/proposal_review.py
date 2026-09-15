"""Pure aggregation of published Proposal and verified tracker facts."""
import tempfile
from pathlib import Path

from capability_map import MapError, parse_map
from proposal_contract import compute


STAGES = {
    "proposal-stage:draft": "awaiting-review",
    "proposal-stage:published": "awaiting-review",
    "proposal-stage:in-review": "in-review",
    "proposal-stage:accepted": "accepted",
    "proposal-stage:rejected": "rejected",
    "proposal-stage:promoted": "promoted-claim",
}


class Review(object):
    def __init__(self, state, review_commit=None, proposal_id=None, platform=None, target=None,
                 issue_id=None, stage=None, diagnostic=None):
        self.state = state
        self.review_commit = review_commit
        self.proposal_id = proposal_id
        self.platform = platform
        self.target = target
        self.issue_id = issue_id
        self.stage = stage
        self.diagnostic = diagnostic


def as_json(result):
    """Serialize stable review facts without snapshot, Issue, or error content."""
    data = {"state": result.state}
    for key, value in (("reviewCommit", result.review_commit),
                       ("proposalId", result.proposal_id), ("platform", result.platform),
                       ("target", result.target), ("issueId", result.issue_id),
                       ("stage", result.stage)):
        if value is not None:
            data[key] = value
    if result.state in ("invalid", "unknown"):
        data["diagnostic"] = "review-%s" % result.state
    elif result.state == "stale":
        data["diagnostic"] = "proposal-stale"
    return data


def _blocked(state):
    return Review(state, diagnostic="review-input-%s" % state)


def _review_map(baseline, review):
    if not isinstance(baseline, str) or not isinstance(review, str):
        return None
    with tempfile.TemporaryDirectory(prefix="sg-proposal-review-") as temp:
        baseline_path = Path(temp) / "baseline-map.md"
        review_path = Path(temp) / "review-map.md"
        baseline_path.write_text(baseline, encoding="utf-8")
        review_path.write_text(review, encoding="utf-8")
        try:
            return parse_map(review_path), compute(str(review_path))
        except MapError:
            return "invalid"
        except (OSError, UnicodeError):
            return None


def review(publication, tracker, platform, target):
    """Interpret already-read facts; never query or mutate Git/tracker state."""
    publication_state = getattr(publication, "state", None)
    if publication_state in ("absent", "invalid", "unknown"):
        return _blocked(publication_state)
    if publication_state != "published":
        return _blocked("unknown")
    tracker_state = getattr(tracker, "state", None)
    if tracker_state in ("absent", "invalid", "unknown"):
        return _blocked(tracker_state)
    if tracker_state != "verified":
        return _blocked("unknown")
    proposal = getattr(publication, "proposal", None)
    review_commit = getattr(publication, "review_commit", None)
    reviewed = _review_map(getattr(publication, "baseline_map", None),
                           getattr(publication, "review_map", None))
    if reviewed == "invalid":
        return _blocked("invalid")
    if proposal is None or not isinstance(review_commit, str) or reviewed is None:
        return _blocked("unknown")
    if (getattr(tracker, "proposal_id", None) != proposal.proposal_id or
            getattr(tracker, "platform", None) != platform or
            getattr(tracker, "target", None) != target):
        return _blocked("invalid")
    review_map, digest = reviewed
    expected_rows = proposal.baseline.module_digests
    actual_rows = dict((row["id"], row["rowDigest"]) for row in digest["rows"])
    if (digest["goalDigest"] != proposal.baseline.goal_digest or
            any(actual_rows.get(module_id) != row_digest
                for module_id, row_digest in expected_rows.items())):
        return Review("stale", review_commit=review_commit, proposal_id=proposal.proposal_id,
                      platform=platform, target=target, issue_id=tracker.issue_id,
                      stage=tracker.stage, diagnostic="proposal-baseline-drifted")
    if proposal.change.module_id in review_map.order:
        return Review("stale", review_commit=review_commit, proposal_id=proposal.proposal_id,
                      platform=platform, target=target, issue_id=tracker.issue_id,
                      stage=tracker.stage, diagnostic="proposal-module-already-present")
    positions = dict((module_id, index) for index, module_id in enumerate(review_map.order))
    dependencies = proposal.change.depends_on
    if any(dependency not in positions for dependency in dependencies):
        return Review("stale", review_commit=review_commit, proposal_id=proposal.proposal_id,
                      platform=platform, target=target, issue_id=tracker.issue_id,
                      stage=tracker.stage, diagnostic="proposal-dependency-missing")
    anchor = proposal.change.anchor
    if anchor != "end":
        anchor_id = anchor[len("after:"):]
        if (anchor_id not in positions or
                any(positions[dependency] > positions[anchor_id] for dependency in dependencies)):
            return Review("stale", review_commit=review_commit, proposal_id=proposal.proposal_id,
                          platform=platform, target=target, issue_id=tracker.issue_id,
                          stage=tracker.stage, diagnostic="proposal-anchor-drifted")
    state = STAGES.get(tracker.stage)
    if state is None:
        return _blocked("invalid")
    return Review(state, review_commit=review_commit, proposal_id=proposal.proposal_id,
                  platform=platform, target=target, issue_id=tracker.issue_id,
                  stage=tracker.stage)
