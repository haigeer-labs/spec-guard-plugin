"""Module documentation decisions are explicit facts, never code-derived guesses."""
import io
import json
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stdout

from documentation_impact import ImpactError, main, parse_impact


BASELINE = """| Concern | Authority | Status | Rationale |
|---|---|---|---|
| product-direction | `docs/product.md` | verified | Product scope. |
| architecture | `docs/architecture.md` | target | Target architecture. |
| developer-entry | `README.md` | verified | Development entry. |
| integration-contract | `docs/api.md` | in-progress | External API contract. |
| operations | — | not-applicable | No operated service. |
"""

SPEC = """# Spec: alpha

## Documentation impact

| Concern | Decision | Rationale |
|---|---|---|
| product-direction | follow | The module stays within approved scope. |
| architecture | update | The target design needs a new module boundary. |
| developer-entry | follow | Existing commands remain valid. |
| integration-contract | create | The new endpoint needs an explicit contract. |
"""

PLAN = """# Plan: alpha

## Documentation delivery

| Concern | Planned artifact | Rationale |
|---|---|---|
| architecture | `docs/architecture.md` | Describe the module boundary. |
| integration-contract | `docs/api.md` | Publish the endpoint contract. |
"""


class DocumentationImpactTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sg-doc-impact-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def valid_project(self):
        self.write("docs/DOCUMENTATION-BASELINE.md", BASELINE)
        self.write("spec/alpha.md", SPEC)
        self.write("tasks/alpha/plan.md", PLAN)

    def test_absent_baseline_keeps_module_silent(self):
        self.write("spec/alpha.md", SPEC)
        self.write("tasks/alpha/plan.md", PLAN)
        impact = parse_impact(self.root, "alpha")
        self.assertEqual(impact.state, "absent")
        self.assertEqual(impact.decisions, {})

    def test_valid_impact_covers_applicable_baseline_concerns(self):
        self.valid_project()
        impact = parse_impact(self.root, "alpha")
        self.assertEqual(impact.state, "valid")
        self.assertEqual(impact.decisions["architecture"].decision, "update")
        self.assertEqual(impact.delivery["integration-contract"].artifact,
                         "docs/api.md")
        self.assertNotIn("operations", impact.decisions)

    def test_missing_applicable_decision_is_rejected(self):
        self.valid_project()
        self.write("spec/alpha.md", SPEC.replace(
            "| developer-entry | follow | Existing commands remain valid. |\n", ""))
        with self.assertRaisesRegex(ImpactError, "developer-entry"):
            parse_impact(self.root, "alpha")

    def test_update_or_create_requires_matching_planned_delivery(self):
        self.valid_project()
        self.write("tasks/alpha/plan.md", PLAN.replace(
            "| integration-contract | `docs/api.md` | Publish the endpoint contract. |\n", ""))
        with self.assertRaisesRegex(ImpactError, "integration-contract"):
            parse_impact(self.root, "alpha")

    def test_update_must_plan_the_baseline_authority(self):
        self.valid_project()
        self.write("tasks/alpha/plan.md", PLAN.replace(
            "`docs/architecture.md`", "`docs/other.md`"))
        with self.assertRaisesRegex(ImpactError, "architecture"):
            parse_impact(self.root, "alpha")

    def test_unknown_decision_and_empty_rationale_are_rejected(self):
        self.valid_project()
        self.write("spec/alpha.md", SPEC.replace("| follow |", "| done |", 1))
        with self.assertRaisesRegex(ImpactError, "unknown decision"):
            parse_impact(self.root, "alpha")
        self.write("spec/alpha.md", SPEC.replace(
            "The module stays within approved scope.", ""))
        with self.assertRaisesRegex(ImpactError, "rationale"):
            parse_impact(self.root, "alpha")

    def test_fenced_example_tables_are_ignored(self):
        self.valid_project()
        self.write("spec/alpha.md", SPEC + """
```markdown
| Concern | Decision | Rationale |
|---|---|---|
| product-direction | pending | Example only. |
```
""")
        self.assertEqual(parse_impact(self.root, "alpha").state, "valid")

    def test_cli_reports_absent_valid_and_invalid_without_writing(self):
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["--project", str(self.root), "--module", "alpha"]), 0)
        self.assertEqual(json.loads(output.getvalue())["state"], "absent")

        self.valid_project()
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["--project", str(self.root), "--module", "alpha"]), 0)
        self.assertEqual(json.loads(output.getvalue())["state"], "valid")

        self.write("tasks/alpha/plan.md", "# Plan\n")
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["--project", str(self.root), "--module", "alpha"]), 1)
        self.assertEqual(json.loads(output.getvalue())["state"], "invalid")


if __name__ == "__main__":
    unittest.main()
