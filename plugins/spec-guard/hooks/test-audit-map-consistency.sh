#!/bin/bash
# 能力图解析与消费者的聚焦回归；不调用远端或 Agent。
set -euo pipefail
HOOKS="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-}"
case "$MODE" in
  ""|--selftest) ;;
  *) printf 'usage: %s [--selftest]\n' "$0" >&2; exit 2 ;;
esac
PYTHONDONTWRITEBYTECODE=1 python3 - "$HOOKS" "$MODE" <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

mode = sys.argv.pop()
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
ORDER = "identity → notifications → billing → reporting"


class MapContract(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="sg-map-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "map with spaces.md"

    def write(self, order=ORDER, table=TABLE):
        self.path.write_text("# Capability Map: sample\n\n" + table +
                             "\nBuild order: " + order + "\n", encoding="utf-8")

    def test_declared_order_is_strictly_serial(self):
        self.write()
        parsed = parse_map(self.path)
        self.assertEqual(parsed.order_groups,
                         [["identity"], ["notifications"], ["billing"], ["reporting"]])
        self.assertEqual(parsed.order, ["identity", "notifications", "billing", "reporting"])
        self.assertEqual(parsed.rows[1].normalized_row, "billing|Payments|identity")

    def test_upstream_comma_group_is_expanded_in_written_order(self):
        self.write("identity → billing, notifications → reporting")
        parsed = parse_map(self.path)
        self.assertEqual(parsed.order_groups,
                         [["identity"], ["billing"], ["notifications"], ["reporting"]])
        self.assertEqual(parsed.order, ["identity", "billing", "notifications", "reporting"])

    def test_linear_ascii_and_ticks(self):
        for order in (ORDER, "`identity` -> `notifications` -> `billing` -> `reporting`"):
            with self.subTest(order=order):
                self.write(order)
                self.assertEqual(parse_map(self.path).order,
                                 ["identity", "notifications", "billing", "reporting"])

    def test_invalid_orders_and_dependencies_fail(self):
        for order in ("", "identity → billing, → reporting", ORDER + " → reporting",
                      "identity → absent → billing → reporting", "identity → billing → reporting"):
            with self.subTest(order=order):
                self.write(order)
                with self.assertRaises(MapError):
                    parse_map(self.path)
        self.write(table=TABLE.replace("Payments | identity", "Payments | reporting"))
        with self.assertRaises(MapError):
            parse_map(self.path)

    def test_cli_contract_is_read_only(self):
        self.write()
        before = self.path.read_bytes()
        result = subprocess.run([sys.executable, str(hooks / "capability-map.py"), str(self.path)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["order"], ["identity", "notifications", "billing", "reporting"])
        self.assertEqual(data["orderGroups"], [[module] for module in data["order"]])
        self.assertEqual(self.path.read_bytes(), before)

    def test_cli_expands_upstream_comma_group_to_serial_layers(self):
        self.write("identity → billing, notifications → reporting")
        result = subprocess.run([sys.executable, str(hooks / "capability-map.py"), str(self.path)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["order"], ["identity", "billing", "notifications", "reporting"])
        self.assertEqual(data["orderGroups"], [[module] for module in data["order"]])


class DigestCompatibility(unittest.TestCase):
    sample = """# Capability Map: sample

## Goal

Protect old digests.

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| `second` | 第二模块 | first |
| first | 根模块 | — |
"""

    def test_legacy_digest_is_stable_and_serial_order_is_parsed(self):
        with tempfile.TemporaryDirectory(prefix="sg-digest-") as temp:
            path = Path(temp) / "map.md"
            path.write_text(self.sample + "\nBuild order: first → second\n", encoding="utf-8")
            result = subprocess.run([sys.executable, str(hooks / "spec-digest.py"), "compute", str(path)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["rows"],
                             [{"id": "second", "rowDigest": "d6b94af161e6"},
                              {"id": "first", "rowDigest": "499ae133d946"}])
            self.assertEqual(parse_map(path).order, ["first", "second"])


class DesktopMapPreview(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="sg-desktop-map-")
        self.addCleanup(self.directory.cleanup)
        self.project = Path(self.directory.name) / "project"
        (self.project / "spec").mkdir(parents=True)
        (self.project / ".agent").mkdir()
        (self.project / ".agent/state.json").write_text('{"tracker":"github"}')
        (self.project / "spec/CAPABILITY-MAP.md").write_text(
            "# Capability Map: Desktop test\n\n" + TABLE + "\nBuild order: " + ORDER + "\n")
        subprocess.run(["git", "init", "-q", str(self.project)], check=True)
        self.bin = Path(self.directory.name) / "bin"
        self.bin.mkdir()
        self.node = shutil.which("node")
        self.assertIsNotNone(self.node, "MCP regression requires Node")

    def preview(self, restricted_path=False):
        request = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {
            "name": "sync_map_preview", "arguments": {"project": str(self.project)}}}
        before = {str(p.relative_to(self.project)): p.read_bytes()
                  for p in self.project.rglob("*") if p.is_file()}
        result = subprocess.run([self.node, str(hooks.parent / "mcp/claude_desktop_server.mjs")],
                                input=json.dumps(request) + "\n", capture_output=True, text=True,
                                env=dict(os.environ, PATH=str(self.bin) if restricted_path else os.environ["PATH"]))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({str(p.relative_to(self.project)): p.read_bytes()
                          for p in self.project.rglob("*") if p.is_file()}, before)
        return json.loads(result.stdout)["result"]

    def test_preview_uses_declared_serial_order(self):
        result = self.preview()
        self.assertFalse(result["isError"], result)
        names = [line.split(": ", 1)[1].split(" — ", 1)[0]
                 for line in result["content"][0]["text"].splitlines()
                 if line.startswith("- Module:")]
        self.assertEqual(names, ["identity", "notifications", "billing", "reporting"])

    def test_bad_graph_is_an_mcp_error(self):
        path = self.project / "spec/CAPABILITY-MAP.md"
        path.write_text(path.read_text().replace("Messages | identity", "Messages | billing"))
        self.assertTrue(self.preview()["isError"])

    def test_python_failure_never_falls_back_to_regex(self):
        valid = {"ok": True, "modules": [{"id": "alpha", "responsibility": "A"}], "order": ["alpha"]}
        for output, code in ((None, 0), ("not JSON", 0), ('{"ok":false,"error":"bad graph"}', 0),
                             ('{"ok":true}', 0), ('{"ok":true,"modules":[],"order":[]}', 0),
                             (json.dumps(valid), 1),
                             (json.dumps(dict(valid, order=["unknown"])), 0),
                             (json.dumps(dict(valid, modules=valid["modules"] * 2, order=["alpha", "alpha"])), 0),
                             (json.dumps(dict(valid, modules=[None])), 0)):
            with self.subTest(output=output, code=code):
                stub = self.bin / "python3"
                if output is not None:
                    stub.write_text("#!" + sys.executable + "\nprint(" + repr(output) + ")\nraise SystemExit(" + str(code) + ")\n")
                    stub.chmod(0o755)
                result = self.preview(restricted_path=True)
                self.assertTrue(result["isError"], result)
                self.assertTrue(result["content"][0]["text"])


class SyncPreflightInstructions(unittest.TestCase):
    def test_actual_instruction_blocks_gate_github_writes(self):
        with tempfile.TemporaryDirectory(prefix="sg-sync-instructions-") as temp:
            project = Path(temp) / "project"
            (project / ".agent").mkdir(parents=True)
            (project / "spec").mkdir()
            (project / ".agent/state.json").write_text('{"tracker":"github"}')
            path = project / "spec/CAPABILITY-MAP.md"
            bin_path = Path(temp) / "bin"
            bin_path.mkdir()
            marker = Path(temp) / "writes"
            gh = bin_path / "gh"
            gh.write_text("#!" + sys.executable + "\nimport os,pathlib\npathlib.Path(os.environ['WRITE_MARKER']).write_text('called')\n")
            gh.chmod(0o755)
            sources = ["skills/spec-github-bridge/SKILL.md", "commands/sync-map.md", "skills/spec-guard-ops/SKILL.md"]
            for source in sources:
                text = (hooks.parent / source).read_text()
                blocks = [block for block in re.findall(r"```bash\n(.*?)\n```", text, re.S) if "capability-map.py" in block]
                self.assertEqual(len(blocks), 1, source + " must provide an executable strict preflight")
                for invalid, missing_parser in ((False, False), (True, False), (False, True)):
                    with self.subTest(source=source, invalid=invalid, missing_parser=missing_parser):
                        if marker.exists():
                            marker.unlink()
                        path.write_text(TABLE + "\nBuild order: " + ("invalid" if invalid else ORDER) + "\n")
                        plugin_root = Path(temp) / "old-plugin" if missing_parser else hooks.parent
                        env = dict(os.environ, PATH=str(bin_path) + os.pathsep + os.environ["PATH"],
                                   PROJECT=str(project), ROOT=str(plugin_root), CLAUDE_PLUGIN_ROOT=str(plugin_root),
                                   SPEC_GUARD_DIGEST=str(plugin_root / "hooks/spec-digest.py"), WRITE_MARKER=str(marker))
                        result = subprocess.run(["/bin/bash", "-c", blocks[0] + "\ngh issue create --title guarded-test\n"],
                                                cwd=project, env=env, capture_output=True, text=True)
                        self.assertEqual(result.returncode == 0, not invalid and not missing_parser,
                                         result.stdout + result.stderr)
                        self.assertEqual(marker.exists(), not invalid and not missing_parser)
                        if not invalid and not missing_parser:
                            self.assertEqual(json.loads(result.stdout)["order"],
                                             ["identity", "notifications", "billing", "reporting"])


def selftest():
    """在隔离插件副本恢复关键漏洞；同一聚焦回归必须变红。"""
    mutations = [
        ("逗号分组被保留为并列执行层", "hooks/capability_map.py",
         'groups = []\n        for segment in segments:\n            groups.extend([[_strip_ticks(item)] for item in segment.split(",")])',
         'groups = [[_strip_ticks(item) for item in segment.split(",")] for segment in segments]'),
        ("摘要只 hash module id", "hooks/spec-digest.py",
         'rows = [(row.module_id, row.normalized_row) for row in parsed.rows]',
         'rows = [(row.module_id, row.module_id) for row in parsed.rows]'),
    ]
    failures = []
    with tempfile.TemporaryDirectory(prefix="sg-map-mutation-") as temp:
        root = Path(temp) / "spec-guard"
        shutil.copytree(hooks.parent, root)
        for name, relative, old, new in mutations:
            target = root / relative
            source = target.read_text(encoding="utf-8")
            if old not in source:
                failures.append(name + "（变异锚点失效）")
                continue
            target.write_text(source.replace(old, new, 1), encoding="utf-8")
            try:
                result = subprocess.run(["/bin/bash", str(root / "hooks/test-audit-map-consistency.sh")],
                                        capture_output=True, text=True, timeout=90)
            finally:
                target.write_text(source, encoding="utf-8")
            if result.returncode == 0:
                failures.append(name + "（变异后仍通过）")
                print("  ❌ " + name)
            else:
                print("  ✅ " + name)
    if failures:
        print("隔离变异自检失败: " + "；".join(failures), file=sys.stderr)
        return 1
    print("隔离变异自检通过")
    return 0


if mode == "--selftest":
    sys.exit(selftest())
unittest.main(verbosity=2)
PY
