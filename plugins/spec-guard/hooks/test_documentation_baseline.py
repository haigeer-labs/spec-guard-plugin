"""The documentation baseline is explicit, narrow, and never inferred from code."""
import io
import json
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stdout

from documentation_baseline import BaselineError, main, parse_baseline


VALID_BASELINE = """# Documentation Baseline

## Baseline

| Concern | Authority | Status | Rationale |
|---|---|---|---|
| product-direction | `docs/product.md` | verified | Approved product scope. |
| architecture | `docs/architecture.md` | target | The approved target state is not fully implemented. |
| developer-entry | `README.md` | verified | Build and test commands are current. |
| consumer-guide | — | not-applicable | This is an internal library without supported end users. |
"""


class DocumentationBaselineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sg-doc-baseline-")
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "DOCUMENTATION-BASELINE.md"

    def write(self, content):
        self.path.write_text(content, encoding="utf-8")
        return parse_baseline(self.path)

    def test_missing_file_is_explicitly_absent(self):
        baseline = parse_baseline(self.path)
        self.assertEqual(baseline.state, "absent")
        self.assertEqual(baseline.entries, {})

    def test_valid_baseline_preserves_target_and_not_applicable(self):
        baseline = self.write(VALID_BASELINE)
        self.assertEqual(baseline.state, "valid")
        self.assertEqual(baseline.entries["architecture"].status, "target")
        self.assertEqual(baseline.entries["consumer-guide"].status, "not-applicable")
        self.assertEqual(baseline.entries["consumer-guide"].authority, None)

    def test_external_authority_is_allowed(self):
        baseline = self.write(VALID_BASELINE.replace(
            "`docs/architecture.md`", "https://example.invalid/architecture"))
        self.assertEqual(baseline.entries["architecture"].authority,
                         "https://example.invalid/architecture")

    def test_fenced_example_table_is_not_treated_as_a_second_baseline(self):
        baseline = self.write(VALID_BASELINE + """
```markdown
| Concern | Authority | Status | Rationale |
|---|---|---|---|
| product-direction | `example.md` | pending | Example only. |
```
""")
        self.assertEqual(baseline.state, "valid")

    def test_broken_symlink_is_invalid_not_absent(self):
        self.path.symlink_to(self.path.parent / "missing.md")
        with self.assertRaisesRegex(BaselineError, "regular file"):
            parse_baseline(self.path)

    def test_missing_universal_concern_is_rejected(self):
        content = VALID_BASELINE.replace(
            "| developer-entry | `README.md` | verified | Build and test commands are current. |\n", "")
        with self.assertRaisesRegex(BaselineError, "developer-entry"):
            self.write(content)

    def test_unknown_status_is_rejected(self):
        content = VALID_BASELINE.replace("| verified |", "| current |", 1)
        with self.assertRaisesRegex(BaselineError, "status"):
            self.write(content)

    def test_not_applicable_requires_a_rationale(self):
        content = VALID_BASELINE.replace(
            "This is an internal library without supported end users.", "")
        with self.assertRaisesRegex(BaselineError, "rationale"):
            self.write(content)

    def test_cli_reports_absent_valid_and_invalid_without_writing(self):
        project = self.path.parent
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["--project", str(project), "--format", "json"]), 0)
        self.assertEqual(json.loads(output.getvalue())["state"], "absent")

        target = project / "docs"
        target.mkdir()
        baseline_path = target / "DOCUMENTATION-BASELINE.md"
        baseline_path.write_text(VALID_BASELINE, encoding="utf-8")
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["--project", str(project), "--format", "json"]), 0)
        self.assertEqual(json.loads(output.getvalue())["state"], "valid")

        baseline_path.write_text("# broken\n", encoding="utf-8")
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["--project", str(project), "--format", "json"]), 1)
        self.assertEqual(json.loads(output.getvalue())["state"], "invalid")


if __name__ == "__main__":
    unittest.main()
