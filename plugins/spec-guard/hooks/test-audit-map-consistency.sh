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


class DigestCompatibility(unittest.TestCase):
    # 黄金值取自 44e3546 的真实 digest + parser；不是用被测实现重算期望。
    sample = """# Capability Map: sample

## Goal

Protect old digests.

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| `second` | 第二模块 | first |
| first | 根模块 | — |
"""
    golden = {"rows": [{"id": "second", "rowDigest": "d6b94af161e6"},
                       {"id": "first", "rowDigest": "499ae133d946"}],
              "order": ["second", "first"], "goalDigest": "23acd1f8517a", "placeholder": False}

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="sg-digest-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "map.md"

    def digest(self, command, *extra):
        result = subprocess.run([sys.executable, str(hooks / "spec-digest.py"), command,
                                 str(self.path), *map(str, extra)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_legacy_goldens_and_order_meaning(self):
        for order in ("", "\nBuild order: first → second\n", "\nBuild order: `first` -> `second`\n"):
            with self.subTest(order=order):
                self.path.write_text(self.sample + order, encoding="utf-8")
                before = self.path.read_bytes()
                self.assertEqual(self.digest("compute"), self.golden)
                if order:
                    self.assertEqual(parse_map(self.path).order, ["first", "second"])
                else:
                    with self.assertRaises(MapError):
                        parse_map(self.path)
                self.assertEqual(self.path.read_bytes(), before)

    def test_formatting_does_not_change_digest(self):
        self.path.write_bytes((self.sample.replace("\n", "  \r\n") +
                               "\r\nBuild order: first → second\r\n").encode("utf-8"))
        self.assertEqual(self.digest("compute"), self.golden)

    def test_real_drift_remains_visible_without_writes(self):
        state = Path(self.directory.name) / "state.json"
        state.write_text(json.dumps({"initiative": {"goalDigest": self.golden["goalDigest"]},
                         "modules": {row["id"]: {"issue": index + 1, "rowDigest": row["rowDigest"]}
                                     for index, row in enumerate(self.golden["rows"])}}))
        original_state = state.read_bytes()
        for sample, goal_stale, rows_stale in (
            (self.sample, False, []),
            (self.sample.replace("Protect old digests.", "Detect real changes."), True, []),
            (self.sample.replace("第二模块", "新的职责"), False, ["second"]),
            (self.sample.replace("第二模块 | first", "第二模块 | —"), False, ["second"]),
        ):
            with self.subTest(goal_stale=goal_stale, rows_stale=rows_stale):
                self.path.write_text(sample, encoding="utf-8")
                before = self.path.read_bytes()
                result = self.digest("check", state)
                self.assertIs(result["ok"], True)
                self.assertEqual(result["goalStale"], goal_stale)
                self.assertEqual(result["rowsStale"], rows_stale)
                self.assertEqual(state.read_bytes(), original_state)
                self.assertEqual(self.path.read_bytes(), before)


unittest.main(verbosity=2)
PY
