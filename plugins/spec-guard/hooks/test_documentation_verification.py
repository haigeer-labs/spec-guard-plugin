"""Delivery reminders report declared facts without pretending to verify content."""
from pathlib import Path
import tempfile
import unittest

from documentation_verification import VerificationError, verify_documentation


BASELINE = """| Concern | Authority | Status | Rationale |
|---|---|---|---|
| product-direction | `docs/product.md` | verified | Product scope. |
| architecture | `docs/architecture.md` | target | Target architecture. |
| developer-entry | `README.md` | verified | Development entry. |
"""

SPEC = """# Spec: alpha

## Documentation impact

| Concern | Decision | Rationale |
|---|---|---|
| product-direction | follow | Existing scope applies. |
| architecture | update | Boundary changed. |
| developer-entry | follow | Commands remain valid. |
"""

PLAN = """# Plan: alpha

## Documentation delivery

| Concern | Planned artifact | Rationale |
|---|---|---|
| architecture | `docs/architecture.md` | Describe the boundary. |
"""


class DocumentationVerificationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sg-doc-verify-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def project(self, outcome=""):
        self.write("docs/DOCUMENTATION-BASELINE.md", BASELINE)
        self.write("spec/alpha.md", SPEC)
        self.write("tasks/alpha/plan.md", PLAN + outcome)

    def test_absent_baseline_is_quiet(self):
        self.write("spec/alpha.md", SPEC)
        self.write("tasks/alpha/plan.md", PLAN)
        self.assertEqual(verify_documentation(self.root, "alpha").state, "absent")

    def test_missing_outcome_is_attention_not_invalid(self):
        self.project()
        result = verify_documentation(self.root, "alpha")
        self.assertEqual(result.state, "attention")
        self.assertIn("architecture", result.attention[0])

    def test_delivered_outcome_with_evidence_is_ready(self):
        self.project("""
## Documentation outcome

| Concern | Outcome | Evidence | Rationale |
|---|---|---|---|
| architecture | delivered | `docs/architecture.md#alpha` | Boundary added. |
""")
        result = verify_documentation(self.root, "alpha")
        self.assertEqual(result.state, "ready")
        self.assertEqual(result.outcomes["architecture"].outcome, "delivered")

    def test_deferred_outcome_remains_attention(self):
        self.project("""
## Documentation outcome

| Concern | Outcome | Evidence | Rationale |
|---|---|---|---|
| architecture | deferred | — | Waiting for architecture review. |
""")
        result = verify_documentation(self.root, "alpha")
        self.assertEqual(result.state, "attention")
        self.assertIn("deferred", result.attention[0])

    def test_delivered_without_evidence_and_unknown_outcome_are_invalid(self):
        self.project("""
## Documentation outcome

| Concern | Outcome | Evidence | Rationale |
|---|---|---|---|
| architecture | delivered | — | Boundary added. |
""")
        with self.assertRaisesRegex(VerificationError, "evidence"):
            verify_documentation(self.root, "alpha")
        self.project("""
## Documentation outcome

| Concern | Outcome | Evidence | Rationale |
|---|---|---|---|
| architecture | published | `docs/architecture.md` | Boundary added. |
""")
        with self.assertRaisesRegex(VerificationError, "unknown outcome"):
            verify_documentation(self.root, "alpha")

    def test_pending_decision_is_attention_even_without_a_delivery_outcome(self):
        self.project()
        self.write("spec/alpha.md", SPEC.replace("| architecture | update |", "| architecture | pending |"))
        self.write("tasks/alpha/plan.md", "# Plan: alpha\n")
        result = verify_documentation(self.root, "alpha")
        self.assertEqual(result.state, "attention")
        self.assertIn("pending", result.attention[0])

    def test_fenced_example_outcome_table_is_ignored(self):
        self.project("""
## Documentation outcome

| Concern | Outcome | Evidence | Rationale |
|---|---|---|---|
| architecture | delivered | `docs/architecture.md#alpha` | Boundary added. |

```markdown
| Concern | Outcome | Evidence | Rationale |
|---|---|---|---|
| architecture | pending | — | Example only. |
```
""")
        self.assertEqual(verify_documentation(self.root, "alpha").state, "ready")


if __name__ == "__main__":
    unittest.main()
