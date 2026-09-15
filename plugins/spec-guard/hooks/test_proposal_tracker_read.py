"""Fixture contract for read-only Proposal tracker recovery; no live service."""
import json
import unittest

from proposal_contract import Baseline, Change, Proposal
from proposal_tracker_read import TrackerRead, as_json, read_tracker, recover_tracker_issue


MARKER = "<!-- spec-guard-proposal:v1 id=gamma -->"


def proposal():
    return Proposal("gamma", MARKER,
                    Baseline("origin", "trunk", "0" * 40, "0" * 12, {}, "alpha"),
                    Change("gamma", "Gamma.", ("alpha",), "after:alpha"))


def github_issue(number=42, body=None, labels=None, repository=None,
                 title="Proposal: gamma"):
    return {
        "number": number,
        "repository": {"full_name": "octo/spec-guard"} if repository is None else repository,
        "title": title,
        "body": MARKER if body is None else body,
        "labels": [{"name": label} for label in (
            ["proposal", "proposal-stage:in-review"] if labels is None else labels)],
    }


def gitlab_issue(iid=9, body=None, labels=None, project_id=17, title="Proposal: gamma",
                 state="opened"):
    return {
        "iid": iid,
        "project_id": project_id,
        "title": title,
        "state": state,
        "description": MARKER if body is None else body,
        "labels": ["proposal", "proposal-stage:published"] if labels is None else labels,
    }


class ProposalTrackerReadFixtures(unittest.TestCase):
    def test_recovers_one_verified_issue_from_each_explicit_platform_container(self):
        github = recover_tracker_issue(proposal(), "github", "octo/spec-guard", {
            "complete": True, "issues": [github_issue()],
        })
        self.assertEqual((github.state, github.issue_id, github.stage),
                         ("verified", 42, "proposal-stage:in-review"))

        gitlab = recover_tracker_issue(proposal(), "gitlab", 17, {
            "complete": True, "issues": [gitlab_issue()],
        })
        self.assertEqual((gitlab.state, gitlab.issue_id, gitlab.stage),
                         ("verified", 9, "proposal-stage:published"))

    def test_recovers_github_search_api_repository_url_shape(self):
        issue = github_issue()
        issue.pop("repository")
        issue["repository_url"] = "https://api.github.com/repos/octo/spec-guard"
        result = recover_tracker_issue(proposal(), "github", "octo/spec-guard", {
            "complete": True, "issues": [issue],
        })
        self.assertEqual((result.state, result.issue_id, result.stage),
                         ("verified", 42, "proposal-stage:in-review"))

    def test_complete_search_without_a_full_body_marker_is_absent(self):
        title_only = github_issue(body="plain text", title=MARKER)
        partial = github_issue(number=43, body="<!-- spec-guard-proposal:v1 id=gamma")
        result = recover_tracker_issue(proposal(), "github", "octo/spec-guard", {
            "complete": True, "issues": [title_only, partial],
        })
        self.assertEqual(result.state, "absent")

    def test_multiple_or_foreign_full_markers_are_invalid(self):
        duplicate = recover_tracker_issue(proposal(), "gitlab", 17, {
            "complete": True, "issues": [gitlab_issue(), gitlab_issue(iid=10)],
        })
        self.assertEqual(duplicate.state, "invalid")

        foreign = recover_tracker_issue(proposal(), "github", "octo/spec-guard", {
            "complete": True,
            "issues": [github_issue(repository={"full_name": "other/project"})],
        })
        self.assertEqual(foreign.state, "invalid")

    def test_incomplete_or_unparseable_search_is_unknown(self):
        incomplete = recover_tracker_issue(proposal(), "github", "octo/spec-guard", {
            "complete": False, "issues": [github_issue()],
        })
        self.assertEqual(incomplete.state, "unknown")

        malformed = recover_tracker_issue(proposal(), "gitlab", 17, {
            "complete": True, "issues": [{"iid": 9, "project_id": 17}],
        })
        self.assertEqual(malformed.state, "unknown")

    def test_label_or_legacy_projection_conflicts_are_invalid(self):
        bad_labels = recover_tracker_issue(proposal(), "gitlab", 17, {
            "complete": True,
            "issues": [gitlab_issue(labels=["proposal", "proposal-stage:draft",
                                              "proposal-stage:accepted"])],
        })
        self.assertEqual(bad_labels.state, "invalid")

        legacy = recover_tracker_issue(proposal(), "github", "octo/spec-guard", {
            "complete": True,
            "issues": [github_issue(body=MARKER + "\n<!-- spec-guard-sync:v2 kind=module -->")],
        })
        self.assertEqual(legacy.state, "invalid")


class ProposalTrackerTransportTests(unittest.TestCase):
    def runner(self, *responses):
        replies = iter(responses)
        calls = []

        def run(args):
            calls.append(args)
            return next(replies)

        return run, calls

    def test_github_reads_every_known_search_page_using_get_argv(self):
        first_page = [github_issue(number=index, body="plain text")
                      for index in range(1, 101)]
        runner, calls = self.runner(
            json.dumps({"total_count": 101, "incomplete_results": False,
                        "items": first_page}),
            json.dumps({"total_count": 101, "incomplete_results": False,
                        "items": [github_issue(number=101)]}),
        )
        result = read_tracker(proposal(), "github", "octo/spec-guard", runner=runner)
        self.assertEqual((result.state, result.issue_id), ("verified", 101))
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(call[:2] == ["gh", "api"] for call in calls))
        self.assertTrue(all(call[2].startswith("search/issues?") for call in calls))
        self.assertTrue(all("is%3Aissue" in call[2] and "page=" in call[2]
                            for call in calls))
        self.assertTrue(all("-X" not in call and "--method" not in call for call in calls))

    def test_gitlab_reads_until_a_short_page_using_get_argv(self):
        first_page = [gitlab_issue(iid=index, body="plain text")
                      for index in range(1, 101)]
        runner, calls = self.runner(
            json.dumps(first_page), json.dumps([gitlab_issue(iid=101, state="closed")]))
        result = read_tracker(proposal(), "gitlab", 17, runner=runner)
        self.assertEqual((result.state, result.issue_id), ("verified", 101))
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(call[:2] == ["glab", "api"] for call in calls))
        self.assertTrue(all(call[2].startswith("projects/17/issues?") for call in calls))
        self.assertTrue(all("search=" in call[2] and "page=" in call[2] and "state=all" in call[2]
                            for call in calls))
        self.assertTrue(all("-X" not in call and "--method" not in call for call in calls))

    def test_transport_failure_or_incomplete_github_response_is_unknown(self):
        failed, _ = self.runner(None)
        self.assertEqual(read_tracker(proposal(), "github", "octo/spec-guard",
                                      runner=failed).state, "unknown")

        incomplete, _ = self.runner(json.dumps({
            "total_count": 1, "incomplete_results": True, "items": [github_issue()],
        }))
        self.assertEqual(read_tracker(proposal(), "github", "octo/spec-guard",
                                      runner=incomplete).state, "unknown")


class ProposalTrackerOutputTests(unittest.TestCase):
    def test_json_exposes_only_safe_verified_facts(self):
        result = TrackerRead("verified", issue_id=42, stage="proposal-stage:in-review")
        data = as_json(result, "github", "octo/spec-guard")
        self.assertEqual(data, {
            "state": "verified", "platform": "github", "target": "octo/spec-guard",
            "issueId": 42, "stage": "proposal-stage:in-review",
        })
        self.assertNotIn(MARKER, json.dumps(data))

    def test_json_sanitizes_invalid_or_unknown_diagnostics(self):
        invalid = as_json(TrackerRead("invalid", diagnostic="token=secret " + MARKER),
                          "gitlab", 17)
        self.assertEqual(invalid["diagnostic"], "tracker-contract-invalid")
        self.assertNotIn("secret", json.dumps(invalid))
        self.assertNotIn(MARKER, json.dumps(invalid))

        unknown = as_json(TrackerRead("unknown", diagnostic="https://token@example.invalid"),
                          "github", "octo/spec-guard")
        self.assertEqual(unknown["diagnostic"], "tracker-read-unavailable")
        self.assertNotIn("example.invalid", json.dumps(unknown))


if __name__ == "__main__":
    unittest.main()
