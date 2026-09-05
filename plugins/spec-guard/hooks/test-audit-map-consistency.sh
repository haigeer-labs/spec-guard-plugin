#!/bin/bash
# 增量覆盖 audit-map-consistency 的已实现契约；不调用远端或 Agent。
set -euo pipefail
HOOKS="$(cd "$(dirname "$0")" && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 - "$HOOKS" <<'PY'
import json
import os
import re
import shutil
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


class GitlabMapInput(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="sg-gitlab-map-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.project = self.root / "project with spaces"
        (self.project / "spec").mkdir(parents=True)
        (self.project / ".agent").mkdir()
        self.state = self.project / ".agent/state.json"
        self.state.write_text(json.dumps({"tracker": "gitlab", "initiative": {}, "modules": {}, "activeModule": ""}))
        self.path = self.project / "spec/CAPABILITY-MAP.md"
        self.log = self.root / "calls.jsonl"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        stub = self.bin / "glab"
        stub.write_text("#!" + sys.executable + "\n" + '''import json, os, pathlib, sys
args = sys.argv[1:]
log = pathlib.Path(os.environ["GLAB_CALL_LOG"])
with log.open("a") as handle:
    handle.write(json.dumps(args) + "\\n")
if args == ["auth", "status"]:
    pass
elif args == ["repo", "view", "--output", "json"]:
    print(json.dumps({"path_with_namespace": "test/project"}))
elif args == ["api", "projects/test%2Fproject"]:
    print(json.dumps({"id": 1}))
elif args[:3] == ["api", "-X", "POST"] and args[3] == "projects/1/issues":
    calls = [json.loads(line) for line in log.read_text().splitlines()]
    print(json.dumps({"iid": sum("POST" in call for call in calls)}))
else:
    raise SystemExit("Unexpected glab call: " + repr(args))
''')
        stub.chmod(0o755)

    def run_sync(self, order=ORDER, table=TABLE, confirm=False):
        self.path.write_text("# Capability Map: Input test\n\n## 目标\n\nTest sync.\n\n## 模块\n\n" +
                             table + "\nBuild order: " + order + "\n\n## 评审记录\n\n- [x] Reviewed\n")
        before = {str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}
        result = subprocess.run(["/bin/bash", str(hooks / "sync-map-gitlab.sh"), *(["--confirm"] if confirm else [])],
                                env=dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                                         CLAUDE_PROJECT_DIR=str(self.project), GLAB_CALL_LOG=str(self.log)),
                                capture_output=True, text=True)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls, before

    def test_parallel_preview_is_ordered_and_read_only(self):
        result, calls, before = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        names = [line.split(": ", 1)[1].split(" — ", 1)[0] for line in result.stdout.splitlines() if "模块: " in line]
        self.assertEqual(names, ["identity", "billing", "notifications", "reporting"])
        self.assertFalse(any("POST" in call for call in calls), calls)
        self.assertEqual({str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}, before)

    def test_invalid_graph_stops_confirm_before_writes(self):
        table = TABLE.replace("Payments | identity", "Payments | reporting")
        result, calls, before = self.run_sync(order="identity → billing → notifications → reporting", table=table, confirm=True)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(any("POST" in call for call in calls), calls)
        self.assertEqual(self.state.read_bytes(), before[".agent/state.json"])

    def test_confirm_consumes_declared_order_not_table_order(self):
        result, calls, _ = self.run_sync(order="identity → notifications, billing → reporting", confirm=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        posts = [call for call in calls if "POST" in call]
        titles = [next(arg[6:] for arg in call if arg.startswith("title=")) for call in posts]
        self.assertEqual(titles, ["Input test", "identity", "notifications", "billing", "reporting"])
        state = json.loads(self.state.read_text())
        self.assertEqual(state["activeModule"], "identity")
        self.assertEqual(state["modules"]["notifications"]["issue"], 3)
        self.assertEqual(len(posts), 5)  # 不创建额外组内关系或额外任务。


class DesktopMapPreview(unittest.TestCase):
    def setUp(self):
        GitlabMapInput.setUp(self)
        subprocess.run(["git", "init", "-q", str(self.project)], check=True)
        self.state.write_text(json.dumps({"tracker": "github"}))
        self.path.write_text("# Capability Map: Desktop test\n\n## 目标\n\nPreview only.\n\n## 模块\n\n" +
                             TABLE + "\nBuild order: identity → notifications, billing → reporting\n")
        self.node = shutil.which("node")
        self.assertIsNotNone(self.node, "MCP regression requires Node")

    def preview(self, restricted_path=False):
        request = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {
            "name": "sync_map_preview", "arguments": {"project": str(self.project)}}}
        before = {str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}
        result = subprocess.run([self.node, str(hooks.parent / "mcp/claude_desktop_server.mjs")],
                                input=json.dumps(request) + "\n", capture_output=True, text=True,
                                env=dict(os.environ, GLAB_CALL_LOG=str(self.log),
                                         PATH=str(self.bin) + ("" if restricted_path else os.pathsep + os.environ["PATH"])))
        self.assertEqual(result.returncode, 0, result.stderr)
        response = json.loads(result.stdout)
        self.assertEqual(response["id"], 1)
        self.assertEqual({str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}, before)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        self.assertFalse(any("POST" in call or "--confirm" in call for call in calls), calls)
        return response["result"]

    def test_github_preview_uses_declared_order(self):
        result = self.preview()
        self.assertIs(result["isError"], False, result)
        text = result["content"][0]["text"]
        names = [line.split(": ", 1)[1].split(" — ", 1)[0] for line in text.splitlines() if line.startswith("- Module:")]
        self.assertEqual(names, ["identity", "notifications", "billing", "reporting"])

    def test_bad_graph_is_an_mcp_error(self):
        self.path.write_text(self.path.read_text().replace("Messages | identity", "Messages | billing"))
        result = self.preview()
        self.assertIs(result["isError"], True, result)
        self.assertNotIn("No local or remote writes were performed.", result["content"][0]["text"])

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
                self.assertIs(result["isError"], True, result)
                self.assertTrue(result["content"][0]["text"])

    def test_gitlab_mcp_preview_still_cannot_write(self):
        self.state.write_text(json.dumps({"tracker": "gitlab", "initiative": {}, "modules": {}}))
        result = self.preview()
        self.assertIs(result["isError"], False, result)
        self.assertIn("未写入任何远端或本地状态", result["content"][0]["text"])


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
                        self.assertEqual(result.returncode == 0, not invalid and not missing_parser, result.stdout + result.stderr)
                        self.assertEqual(marker.exists(), not invalid and not missing_parser)
                        if not invalid and not missing_parser:
                            self.assertEqual(json.loads(result.stdout)["order"], ["identity", "billing", "notifications", "reporting"])


unittest.main(verbosity=2)
PY
