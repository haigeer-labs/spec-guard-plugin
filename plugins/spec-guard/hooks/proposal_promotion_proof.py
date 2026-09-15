"""Read-only remote-default proof that a Proposal module was promoted."""
import subprocess
import tempfile
from pathlib import Path

from capability_map import MapError, parse_map
from proposal_contract import COMMIT


class Proof(object):
    def __init__(self, state, review_commit=None, proposal_id=None, module_id=None,
                 promotion_commit=None, diagnostic=None):
        self.state = state
        self.review_commit = review_commit
        self.proposal_id = proposal_id
        self.module_id = module_id
        self.promotion_commit = promotion_commit
        self.diagnostic = diagnostic


def as_json(result):
    """Serialize safe proof identifiers without remote, map, or raw-error data."""
    data = {"state": result.state}
    for key, value in (("reviewCommit", result.review_commit),
                       ("proposalId", result.proposal_id),
                       ("moduleId", result.module_id),
                       ("promotionCommit", result.promotion_commit)):
        if value is not None:
            data[key] = value
    if result.state in ("invalid", "unknown", "not-accepted"):
        data["diagnostic"] = "promotion-%s" % result.state
    return data


def _remote(project, name):
    try:
        result = subprocess.run(["git", "-C", str(project), "remote", "get-url", name],
                                text=True, capture_output=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 and result.stdout.strip() else None


def _run(args):
    try:
        result = subprocess.run(args, text=True, capture_output=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result if result.returncode == 0 else None


def _head(url):
    result = _run(["git", "ls-remote", "--symref", url, "HEAD"])
    if not result:
        return None
    branch = None
    commit = None
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[0] == "ref:" and fields[2] == "HEAD":
            if fields[1].startswith("refs/heads/"):
                branch = fields[1][len("refs/heads/"):]
        elif len(fields) == 2 and fields[1] == "HEAD":
            commit = fields[0]
    return (branch, commit) if branch and COMMIT.fullmatch(commit or "") else None


def _show(repo, commit, path):
    result = _run(["git", "-C", str(repo), "show", "%s:%s" % (commit, path)])
    return result.stdout if result else None


def _map(repo, commit, temp):
    text = _show(repo, commit, "spec/CAPABILITY-MAP.md")
    if text is None:
        return "invalid"
    path = Path(temp) / ("map-%s.md" % commit)
    try:
        path.write_text(text, encoding="utf-8")
        return parse_map(path)
    except (MapError, OSError, UnicodeError):
        return "invalid"


def _matches(proposal, capability_map):
    rows = dict((row.module_id, row) for row in capability_map.rows)
    row = rows.get(proposal.change.module_id)
    if (row is None or row.responsibility != proposal.change.responsibility or
            tuple(row.depends_on) != tuple(proposal.change.depends_on)):
        return False
    position = capability_map.order.index(proposal.change.module_id)
    if proposal.change.anchor == "end":
        return position == len(capability_map.order) - 1
    anchor = proposal.change.anchor[len("after:"):]
    return (anchor in capability_map.order and
            position == capability_map.order.index(anchor) + 1)


def _first_parent(repo, commit):
    result = _run(["git", "-C", str(repo), "rev-list", "--parents", "-n", "1", commit])
    if not result:
        return None
    fields = result.stdout.split()
    return fields[1] if len(fields) >= 2 and fields[0] == commit else "invalid"


def _blocked(state):
    return Proof(state, diagnostic="promotion-input-%s" % state)


def prove(project, publication, review_result, remote="origin"):
    """Prove the first matching module commit from a fresh remote-default snapshot."""
    publication_state = getattr(publication, "state", None)
    if publication_state in ("absent", "invalid", "unknown"):
        return _blocked(publication_state)
    if publication_state != "published":
        return _blocked("unknown")
    review_state = getattr(review_result, "state", None)
    if review_state in ("invalid", "unknown"):
        return _blocked(review_state)
    if review_state != "accepted":
        return _blocked("not-accepted")
    proposal = getattr(publication, "proposal", None)
    review_commit = getattr(publication, "review_commit", None)
    if (proposal is None or not isinstance(review_commit, str) or
            not COMMIT.fullmatch(review_commit) or
            getattr(review_result, "review_commit", None) != review_commit or
            getattr(review_result, "proposal_id", None) != proposal.proposal_id):
        return _blocked("invalid")
    url = _remote(project, remote)
    observed = _head(url) if url else None
    if not observed:
        return _blocked("unknown")
    branch, observed_commit = observed
    with tempfile.TemporaryDirectory(prefix="sg-proposal-promotion-proof-") as temp:
        repo = Path(temp) / "snapshot.git"
        if not _run(["git", "init", "--bare", str(repo)]):
            return _blocked("unknown")
        fetched = _run(["git", "-C", str(repo), "fetch", "--no-tags", url,
                        "refs/heads/%s" % branch])
        tip = _run(["git", "-C", str(repo), "rev-parse", "FETCH_HEAD"])
        if not fetched or not tip or tip.stdout.strip() != observed_commit:
            return _blocked("unknown")
        ancestor = _run(["git", "-C", str(repo), "merge-base", "--is-ancestor",
                         review_commit, observed_commit])
        if not ancestor:
            return _blocked("invalid")
        commits = _run(["git", "-C", str(repo), "rev-list", "--first-parent",
                        "--reverse", "%s..%s" % (review_commit, observed_commit)])
        if not commits:
            return _blocked("unknown")
        for commit in commits.stdout.splitlines():
            capability_map = _map(repo, commit, temp)
            if capability_map == "invalid":
                return _blocked("invalid")
            if proposal.change.module_id not in capability_map.order:
                continue
            parent = _first_parent(repo, commit)
            if parent is None:
                return _blocked("unknown")
            if parent == "invalid":
                return _blocked("invalid")
            parent_map = _map(repo, parent, temp)
            if parent_map == "invalid":
                return _blocked("invalid")
            if proposal.change.module_id in parent_map.order or not _matches(proposal, capability_map):
                return _blocked("invalid")
            return Proof("proved", review_commit=review_commit, proposal_id=proposal.proposal_id,
                         module_id=proposal.change.module_id, promotion_commit=commit)
    return _blocked("invalid")
