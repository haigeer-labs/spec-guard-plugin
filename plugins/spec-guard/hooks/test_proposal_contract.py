"""Proposal contract tests: explicit facts only, with no Git or tracker writes."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

from proposal_contract import ContractError, parse_proposal, validate_proposal, validate_tracker


_digest_spec = importlib.util.spec_from_file_location(
    "spec_guard_digest", Path(__file__).with_name("spec-digest.py"))
_digest_module = importlib.util.module_from_spec(_digest_spec)
_digest_spec.loader.exec_module(_digest_module)
compute = _digest_module.compute


MAP = """# Capability Map: Candidate pool

## 目标

Keep candidate requirements reviewable.

## 模块

| Module id | Responsibility | Depends on |
| --- | --- | --- |
| alpha | First module | — |
| beta | Second module | alpha |

Build order: alpha → beta
"""


class ProposalContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sg-proposal-contract-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.map_path = self.root / "CAPABILITY-MAP.md"
        self.map_path.write_text(MAP, encoding="utf-8")

    def write_proposal(self, body):
        path = self.root / "proposal.md"
        path.write_text(body, encoding="utf-8")
        return path

    def proposal(self, change_type="new-module", extra=""):
        digest = compute(str(self.map_path))
        rows = ["| %s | %s |" % (row["id"], row["rowDigest"])
                for row in digest["rows"]]
        lines = [
            "# Proposal: Add gamma",
            "<!-- spec-guard-proposal:v1 id=gamma -->",
            "",
            "## Summary",
            "",
            "Gamma is a separate capability.",
            "",
            "## Capability map baseline",
            "",
            "| Field | Value |",
            "| --- | --- |",
            "| Remote | origin |",
            "| Default branch | main |",
            "| Commit | 0123456789abcdef0123456789abcdef01234567 |",
            "| Capability map | spec/CAPABILITY-MAP.md |",
            "| Goal digest | %s |" % digest["goalDigest"],
            "| Build order | alpha → beta |",
            "",
            "### Module digests",
            "",
            "| Module id | Row digest |",
            "| --- | --- |",
        ] + rows + [
            "",
            "## Change",
            "",
            "| Field | Value |",
            "| --- | --- |",
            "| Type | %s |" % change_type,
            "| Module id | gamma |",
            "| Responsibility | Gamma responsibility. |",
            "| Depends on | alpha |",
            "| Build-order anchor | after:alpha |",
            "",
            "## Tracker contract",
            "",
            "| Field | Value |",
            "| --- | --- |",
            "| Proposal id | gamma |",
            "| Identity label | proposal |",
            "| Stage label namespace | proposal-stage: |",
            extra,
        ]
        return "\n".join(lines)

    def test_valid_proposal_matches_explicit_capability_map_baseline(self):
        proposal = self.write_proposal(self.proposal())
        parsed = validate_proposal(proposal, self.map_path)
        self.assertEqual(parsed.proposal_id, "gamma")
        self.assertEqual(parsed.change.module_id, "gamma")
        self.assertEqual(parsed.change.depends_on, ("alpha",))

    def test_duplicate_or_partial_document_marker_is_rejected(self):
        duplicate = self.write_proposal(self.proposal(
            extra="<!-- spec-guard-proposal:v1 id=gamma -->"))
        with self.assertRaisesRegex(ContractError, "marker"):
            parse_proposal(duplicate)

        partial = self.write_proposal(self.proposal().replace(
            "<!-- spec-guard-proposal:v1 id=gamma -->", "<!-- spec-guard-proposal:v1 id=gamma", 1))
        with self.assertRaisesRegex(ContractError, "marker"):
            parse_proposal(partial)

    def test_fenced_examples_do_not_create_extra_contract_facts(self):
        proposal = self.write_proposal(self.proposal(extra="""
```markdown
<!-- spec-guard-proposal:v1 id=wrong -->
## Change
| Field | Value |
| --- | --- |
| Type | remove-module |
```
"""))
        self.assertEqual(validate_proposal(proposal, self.map_path).proposal_id, "gamma")

    def test_unsupported_change_and_stale_baseline_are_rejected(self):
        unsupported = self.write_proposal(self.proposal(change_type="remove-module"))
        with self.assertRaisesRegex(ContractError, "new-module"):
            validate_proposal(unsupported, self.map_path)

        stale = self.write_proposal(self.proposal().replace("| Build order | alpha → beta |",
                                                             "| Build order | beta → alpha |"))
        with self.assertRaisesRegex(ContractError, "Build order"):
            validate_proposal(stale, self.map_path)

    def test_baseline_and_change_relationships_fail_closed(self):
        missing_digest = self.write_proposal(self.proposal().replace(
            "| beta | %s |\n" % compute(str(self.map_path))["rows"][1]["rowDigest"], ""))
        with self.assertRaisesRegex(ContractError, "Module digests"):
            validate_proposal(missing_digest, self.map_path)

        misplaced = self.write_proposal(self.proposal().replace(
            "| Depends on | alpha |\n| Build-order anchor | after:alpha |",
            "| Depends on | beta |\n| Build-order anchor | after:alpha |"))
        with self.assertRaisesRegex(ContractError, "anchor"):
            validate_proposal(misplaced, self.map_path)

        non_short_ref = self.write_proposal(self.proposal().replace(
            "| Default branch | main |", "| Default branch | refs/heads/main |"))
        with self.assertRaisesRegex(ContractError, "baseline"):
            parse_proposal(non_short_ref)

    def test_tracker_requires_one_full_marker_and_one_allowed_stage_label(self):
        proposal = parse_proposal(self.write_proposal(self.proposal()))
        issue_body = "Proposal discussion\n\n%s\n" % proposal.marker
        validate_tracker(proposal, issue_body, ["proposal", "proposal-stage:in-review"])

        with self.assertRaisesRegex(ContractError, "stage"):
            validate_tracker(proposal, issue_body,
                             ["proposal", "proposal-stage:draft", "proposal-stage:accepted"])
        with self.assertRaisesRegex(ContractError, "marker"):
            validate_tracker(proposal, "<!-- spec-guard-proposal:v1 id=gamma",
                             ["proposal", "proposal-stage:draft"])

    def test_validation_never_mutates_the_proposal_or_map(self):
        proposal = self.write_proposal(self.proposal())
        before = (proposal.read_bytes(), self.map_path.read_bytes())
        validate_proposal(proposal, self.map_path)
        self.assertEqual(before, (proposal.read_bytes(), self.map_path.read_bytes()))


if __name__ == "__main__":
    unittest.main()
