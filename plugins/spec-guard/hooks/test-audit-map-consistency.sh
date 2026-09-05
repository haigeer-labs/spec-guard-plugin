#!/bin/bash
# 增量覆盖 audit-map-consistency 的已实现契约；不调用远端或 Agent。
set -euo pipefail
HOOKS="$(cd "$(dirname "$0")" && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 - "$HOOKS" <<'PY'
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

hooks = Path(sys.argv.pop())
sys.path.insert(0, str(hooks))
from capability_map import MapError, parse_map

TABLE = """| Module id | Responsibility | Depends on |
|---|---|---|
| identity | Accounts | — |
| billing | Payments | identity |
| notifications | Messages | identity |
| reporting | Reports | billing, notifications |
"""
ORDER = "identity → billing, notifications → reporting"


class MapContract(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="sg-map-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "map with spaces.md"

    def write(self, order=ORDER, table=TABLE, suffix=""):
        self.path.write_text("# Capability Map: sample\n\n" + table +
                             "\nBuild order: " + order + "\n" + suffix, encoding="utf-8")

    def test_parallel_order(self):
        self.write()
        parsed = parse_map(self.path)
        self.assertEqual(parsed.order_groups, [["identity"], ["billing", "notifications"], ["reporting"]])
        self.assertEqual(parsed.order, ["identity", "billing", "notifications", "reporting"])
        self.assertEqual(parsed.rows[1].responsibility, "Payments")
        self.assertEqual(parsed.rows[1].normalized_row, "billing|Payments|identity")

    def test_linear_ascii_and_ticks(self):
        for order in ("identity → billing → notifications → reporting",
                      "`identity` -> `billing`, `notifications` -> `reporting`"):
            with self.subTest(order=order):
                self.write(order)
                self.assertEqual(parse_map(self.path).order,
                                 ["identity", "billing", "notifications", "reporting"])

    def test_empty_root_dependency_is_valid(self):
        for row in ("| identity | Accounts |  |", "|identity|Accounts||"):
            with self.subTest(row=row):
                self.write(table=TABLE.replace("| identity | Accounts | — |", row))
                self.assertEqual(parse_map(self.path).rows[0].depends_on, [])

    def test_table_header_is_required_and_validated(self):
        for table in (TABLE.replace("|---|---|---|\n", ""),
                      TABLE.replace("Responsibility", "Unspecified"), ""):
            with self.subTest(table=table):
                self.write(table=table)
                with self.assertRaises(MapError):
                    parse_map(self.path)

    def test_invalid_orders(self):
        for order in ("", "identity → billing, → reporting", ORDER + " → reporting",
                      "identity → absent, notifications → reporting",
                      "identity → billing → reporting", "→ " + ORDER,
                      "billing, notifications → identity → reporting"):
            with self.subTest(order=order):
                self.write(order)
                with self.assertRaises(MapError):
                    parse_map(self.path)

    def test_invalid_dependencies_and_modules(self):
        for table in (TABLE.replace("Messages | identity", "Messages | billing"),
                      TABLE.replace("Accounts | —", "Accounts | reporting"),
                      TABLE.replace("Payments | identity", "Payments | billing"),
                      TABLE.replace("Payments | identity", "Payments | absent"),
                      TABLE.replace("Payments | identity", "Payments | identity,"),
                      TABLE.replace("| billing |", "| identity |"),
                      TABLE.replace("| billing |", "| Billing_Module |"),
                      TABLE.replace("| billing | Payments | identity |", "| billing | Payments |")):
            with self.subTest(table=table):
                self.write(table=table)
                with self.assertRaises(MapError):
                    parse_map(self.path)

    def test_ignore_unrelated_tables_and_fenced_examples(self):
        self.write(suffix="\n## Notes\n| Risk | Impact | Mitigation |\n|---|---|---|\n"
                   "| risk | high | tests |\n\n```markdown\n" + TABLE +
                   "Build order: incorrect\n```\n")
        self.assertEqual(len(parse_map(self.path).rows), 4)

    def test_ambiguous_tables_or_orders_fail(self):
        for suffix in ("\n" + TABLE, "\nBuild order: " + ORDER):
            with self.subTest(suffix=suffix):
                self.write(suffix=suffix)
                with self.assertRaises(MapError):
                    parse_map(self.path)

    def test_cli_contract_and_read_only(self):
        self.write()
        before = self.path.read_bytes()
        result = subprocess.run([sys.executable, str(hooks / "capability-map.py"), str(self.path)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertIs(data["ok"], True)
        self.assertEqual(data["orderGroups"], parse_map(self.path).order_groups)
        self.assertEqual(data["modules"][1], {"id": "billing", "responsibility": "Payments", "dependsOn": ["identity"]})
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])
        self.write("incorrect")
        for path in (self.path, self.path.parent / "missing.md"):
            result = subprocess.run([sys.executable, str(hooks / "capability-map.py"), str(path)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            data = json.loads(result.stdout)
            self.assertIs(data["ok"], False)
            self.assertTrue(data["error"])


unittest.main(verbosity=2)
PY
