"""Promotion-proof fixtures begin with safe input-state precedence."""
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from proposal_contract import compute
from proposal_publication import read_published
from proposal_promotion_proof import as_json, prove
from proposal_review import Review, review
from proposal_tracker_read import TrackerRead


_HOOKS = Path(__file__).parent
_DIGEST_SPEC = importlib.util.spec_from_file_location("proposal_digest", _HOOKS / "spec-digest.py")
_DIGEST = importlib.util.module_from_spec(_DIGEST_SPEC)
_DIGEST_SPEC.loader.exec_module(_DIGEST)

BASE_MAP = """# Capability Map: promotion fixture

## 目标

Keep promotion facts explicit.

## 模块

| Module id | Responsibility | Depends on |
| --- | --- | --- |
| alpha | Existing capability | — |

Build order: alpha
"""

PROMOTION_MAP = BASE_MAP.replace(
    "| alpha | Existing capability | — |",
    "| alpha | Existing capability | — |\n| gamma | Gamma. | alpha |").replace(
        "Build order: alpha", "Build order: alpha → gamma")


class PromotionFixture(unittest.TestCase):
    promotion_map = PROMOTION_MAP
    merge_promotion = False

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sg-proposal-promotion-proof-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.seed = self.root / "seed"
        self.remote = self.root / "remote.git"
        self.consumer = self.root / "consumer"
        self.git(self.root, "init", "--bare", "-b", "trunk", str(self.remote))
        self.git(self.root, "init", "-b", "trunk", str(self.seed))
        self.git(self.seed, "config", "user.email", "test@example.invalid")
        self.git(self.seed, "config", "user.name", "test")
        (self.seed / "spec").mkdir()
        (self.seed / "spec/CAPABILITY-MAP.md").write_text(BASE_MAP, encoding="utf-8")
        self.git(self.seed, "add", "spec/CAPABILITY-MAP.md")
        self.git(self.seed, "commit", "-m", "baseline")
        self.baseline = self.git(self.seed, "rev-parse", "HEAD").strip()
        self.write_proposal()
        self.git(self.seed, "add", "spec/proposals/gamma.md")
        self.git(self.seed, "commit", "-m", "publish proposal")
        self.git(self.seed, "remote", "add", "origin", str(self.remote))
        self.git(self.seed, "push", "origin", "trunk")
        self.git(self.root, "clone", str(self.remote), str(self.consumer))
        self.publication = read_published(self.consumer, "gamma")
        self.accepted = review(
            self.publication,
            TrackerRead("verified", issue_id=42, stage="proposal-stage:accepted",
                        proposal_id="gamma", platform="github", target="octo/spec-guard"),
            "github", "octo/spec-guard")
        self.assertEqual(self.accepted.state, "accepted")
        if self.merge_promotion:
            self.git(self.seed, "checkout", "-b", "proposal-gamma")
            (self.seed / "spec/CAPABILITY-MAP.md").write_text(self.promotion_map, encoding="utf-8")
            self.git(self.seed, "add", "spec/CAPABILITY-MAP.md")
            self.git(self.seed, "commit", "-m", "prepare gamma")
            self.feature_commit = self.git(self.seed, "rev-parse", "HEAD").strip()
            self.git(self.seed, "checkout", "trunk")
            (self.seed / "README.md").write_text("mainline change\n", encoding="utf-8")
            self.git(self.seed, "add", "README.md")
            self.git(self.seed, "commit", "-m", "mainline change")
            self.git(self.seed, "merge", "--no-ff", "proposal-gamma", "-m", "merge gamma")
        else:
            (self.seed / "spec/CAPABILITY-MAP.md").write_text(self.promotion_map,
                                                               encoding="utf-8")
            self.git(self.seed, "add", "spec/CAPABILITY-MAP.md")
            self.git(self.seed, "commit", "-m", "promote gamma")
        self.promotion_commit = self.git(self.seed, "rev-parse", "HEAD").strip()
        self.git(self.seed, "push", "origin", "trunk")

    def git(self, cwd, *args):
        result = subprocess.run(["git", "-C", str(cwd)] + list(args), text=True,
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def write_proposal(self):
        digest = _DIGEST.compute(str(self.seed / "spec/CAPABILITY-MAP.md"))
        rows = "\n".join("| %s | %s |" % (item["id"], item["rowDigest"])
                         for item in digest["rows"])
        text = """# Proposal: Add gamma
<!-- spec-guard-proposal:v1 id=gamma -->

## Summary

Gamma is separate.

## Capability map baseline

| Field | Value |
| --- | --- |
| Remote | origin |
| Default branch | trunk |
| Commit | %s |
| Capability map | spec/CAPABILITY-MAP.md |
| Goal digest | %s |
| Build order | alpha |

### Module digests

| Module id | Row digest |
| --- | --- |
%s

## Change

| Field | Value |
| --- | --- |
| Type | new-module |
| Module id | gamma |
| Responsibility | Gamma. |
| Depends on | alpha |
| Build-order anchor | after:alpha |

## Tracker contract

| Field | Value |
| --- | --- |
| Proposal id | gamma |
| Identity label | proposal |
| Stage label namespace | proposal-stage: |
""" % (self.baseline, digest["goalDigest"], rows)
        (self.seed / "spec/proposals").mkdir()
        (self.seed / "spec/proposals/gamma.md").write_text(text, encoding="utf-8")

class PromotionProofStateTests(PromotionFixture):
    def test_nonaccepted_invalid_and_unknown_reviews_stop_before_remote_access(self):
        cases = (
            (Review("awaiting-review"), "not-accepted"),
            (Review("invalid"), "invalid"),
            (Review("unknown"), "unknown"),
            (Review("accepted", review_commit="b" * 40, proposal_id="gamma",
                    platform="github", target="octo/spec-guard"), "invalid"),
        )
        with patch("proposal_promotion_proof._remote") as remote:
            for review_result, expected in cases:
                result = prove(self.consumer, self.publication, review_result)
                self.assertEqual(result.state, expected)
        remote.assert_not_called()


class PromotionProofRemoteTests(PromotionFixture):
    def test_proves_the_first_remote_commit_and_ignores_dirty_consumer_files(self):
        dirty = self.consumer / "spec/CAPABILITY-MAP.md"
        dirty.write_text("not shared remote fact", encoding="utf-8")
        (self.seed / "README.md").write_text("later unrelated commit\n", encoding="utf-8")
        self.git(self.seed, "add", "README.md")
        self.git(self.seed, "commit", "-m", "later change")
        self.git(self.seed, "push", "origin", "trunk")

        result = prove(self.consumer, self.publication, self.accepted)

        self.assertEqual(result.state, "proved")
        self.assertEqual(result.review_commit, self.publication.review_commit)
        self.assertEqual(result.promotion_commit, self.promotion_commit)
        self.assertEqual((result.proposal_id, result.module_id), ("gamma", "gamma"))
        self.assertEqual(dirty.read_text(encoding="utf-8"), "not shared remote fact")

    def test_unavailable_remote_is_unknown(self):
        with patch("proposal_promotion_proof._head", return_value=None):
            self.assertEqual(prove(self.consumer, self.publication, self.accepted).state, "unknown")

    def test_json_exposes_only_safe_proof_identifiers(self):
        result = prove(self.consumer, self.publication, self.accepted)
        data = as_json(result)
        self.assertEqual(data["state"], "proved")
        self.assertEqual(data["promotionCommit"], self.promotion_commit)
        self.assertEqual(data["proposalId"], "gamma")
        self.assertNotIn(str(self.remote), json.dumps(data))
        self.assertNotIn("Capability Map", json.dumps(data))


class InvalidPromotionProofRemoteTests(PromotionFixture):
    promotion_map = PROMOTION_MAP.replace("| gamma | Gamma. | alpha |",
                                          "| gamma | Different responsibility | alpha |")

    def test_mismatched_first_remote_module_is_invalid(self):
        self.assertEqual(prove(self.consumer, self.publication, self.accepted).state, "invalid")


class MergePromotionProofRemoteTests(PromotionFixture):
    merge_promotion = True

    def test_proves_the_merge_commit_not_the_merged_branch_commit(self):
        result = prove(self.consumer, self.publication, self.accepted)
        self.assertEqual(result.state, "proved")
        self.assertEqual(result.promotion_commit, self.promotion_commit)
        self.assertNotEqual(result.promotion_commit, self.feature_commit)


if __name__ == "__main__":
    unittest.main()
