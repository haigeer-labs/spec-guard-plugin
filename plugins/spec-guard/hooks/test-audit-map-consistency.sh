#!/bin/bash
# 增量覆盖 audit-map-consistency 的已实现契约；不调用远端或 Agent。
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
import re
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

mode = sys.argv.pop()
hooks = Path(sys.argv.pop())
sys.path.insert(0, str(hooks))
from capability_map import MapError, parse_map
import parallel_safety_gate as safety
from parallel_safety_gate import BoundaryError, FIELDS, classify_group, parse_boundary

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


class LexicalBoundaries(unittest.TestCase):
    def boundary(self, paths):
        return dict({field: [] for field in FIELDS}, paths=paths)

    def test_component_overlap_and_raw_evidence(self):
        for left in ("src/", "./src", "src//", "src/./", ".", "./"):
            with self.subTest(left=left):
                result = classify_group({"alpha": self.boundary([left]),
                                         "beta": self.boundary(["src/file.py"])})
                self.assertEqual(result["classification"], "sequential-required", result)
                self.assertTrue(any(e["category"] == "paths" for e in result["evidence"]))
                self.assertEqual(result["pathDeclarations"]["alpha"], [{"raw": left,
                                 "normalized": "." if left in (".", "./") else "src"}])
        result = classify_group({"alpha": self.boundary(["./src//file.py"]),
                                 "beta": self.boundary(["src/file.py"])})
        self.assertEqual(result["classification"], "sequential-required", result)

    def test_distinct_components_are_not_parent_paths(self):
        result = classify_group({"alpha": self.boundary(["src/"]), "beta": self.boundary(["src-old/file.py"])})
        self.assertEqual(result["classification"], "needs-review", result)  # 无项目上下文。
        self.assertFalse(any(e["category"] == "paths" for e in result["evidence"]))

    def test_file_and_direct_input_share_validation(self):
        bad_paths = ["", " ", " src", "src ", "..", "src/../out", "/tmp/a", "C:/temp", "C:temp",
                     "//server/share", "src\\file", "*.py", "src/?", "src/[ab]", "src/\x00x", "src/\nx", "src/\x7fx"]
        invalid = [self.boundary([path]) for path in bad_paths]
        invalid += [dict(self.boundary(["src/a"]), **{field: value})
                    for field in FIELDS for value in (None, "src", [1], {}, [""])]
        invalid += [None, [], {}, dict(self.boundary([]), unexpected=[])]
        with tempfile.TemporaryDirectory(prefix="sg-boundary-") as temp:
            path = Path(temp) / "module.md"
            for boundary in invalid:
                with self.subTest(boundary=boundary):
                    path.write_text("## Parallel Boundary\n```json\n" + json.dumps(boundary) + "\n```\n")
                    with self.assertRaises(BoundaryError):
                        parse_boundary(path)
                    result = classify_group({"alpha": boundary, "beta": self.boundary(["other/file.py"])})
                    self.assertEqual(result["classification"], "needs-review", result)
                    self.assertTrue(result["evidence"])
            path.write_text("## Parallel Boundary\n```json\n" + json.dumps(self.boundary(["./src//"])) + "\n```\n")
            self.assertEqual(parse_boundary(path)["paths"], ["./src//"])

    def test_empty_boundaries_and_mixed_conflicts(self):
        for boundaries in ({}, {"alpha": self.boundary([]), "beta": self.boundary([])}):
            self.assertEqual(classify_group(boundaries)["classification"], "needs-review")
        for field in ("migrations", "globalConfig", "testResources", "publicInterfaces"):
            result = classify_group({"alpha": dict(self.boundary(["src/a"]), **{field: ["shared"]}),
                                     "beta": dict(self.boundary(["src/b"]), **{field: ["shared"]}),
                                     "unknown": None})
            self.assertEqual(result["classification"], "sequential-required", result)
            self.assertTrue(any(e["category"] == field for e in result["evidence"]))
            self.assertTrue(any(e["category"] == "invalid-boundary" for e in result["evidence"]))


class PhysicalBoundaries(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="sg-physical-")
        self.addCleanup(self.directory.cleanup)
        self.project = Path(self.directory.name) / "project"
        self.project.mkdir()
        (self.project / "src").mkdir()
        (self.project / "src/a.py").write_text("a")
        (self.project / "src/b.py").write_text("b")

    def classify(self, left, right="src/b.py", project=True):
        boundaries = {"alpha": dict({field: [] for field in FIELDS}, paths=[left]),
                      "beta": dict({field: [] for field in FIELDS}, paths=[right])}
        return classify_group(boundaries, project=self.project) if project else classify_group(boundaries)

    def test_no_context_is_not_physical_evidence(self):
        result = self.classify("src/a.py", project=False)
        self.assertEqual(result["classification"], "needs-review", result)
        self.assertTrue(any(e["category"] == "physical-context" for e in result["evidence"]))

    def test_normal_existing_and_future_paths_are_limited_checks(self):
        for path, status in (("src/a.py", "checked"), ("new/feature.py", "not-created")):
            result = self.classify(path)
            self.assertEqual(result["classification"], "manual-parallel-eligible", result)
            self.assertEqual(result["pathDeclarations"]["alpha"][0]["physical"]["status"], status)
            self.assertIn("不证明物理隔离", result["scopeNotice"])

    def test_symlinks_do_not_reach_external_canary(self):
        outside = Path(self.directory.name) / "outside"
        outside.mkdir()
        canary = outside / "canary"
        canary.write_text("must not be read")
        (self.project / "linked").symlink_to(outside, target_is_directory=True)
        (self.project / "leaf").symlink_to(canary)
        (self.project / "broken").symlink_to(outside / "absent")
        (self.project / "internal").symlink_to(self.project / "src", target_is_directory=True)
        original_stat, original_open = os.stat, os.open
        calls = []
        def guarded_stat(path, *args, **kwargs):
            calls.append(os.fspath(path))
            self.assertNotIn("canary", os.fspath(path))
            self.assertNotIn("outside", os.fspath(path))
            return original_stat(path, *args, **kwargs)
        def guarded_open(path, *args, **kwargs):
            self.assertNotIn("canary", os.fspath(path))
            self.assertNotIn("outside", os.fspath(path))
            return original_open(path, *args, **kwargs)
        for path in ("linked/canary", "leaf", "broken", "internal/a.py"):
            with self.subTest(path=path), mock.patch.object(safety.os, "stat", side_effect=guarded_stat), \
                    mock.patch.object(safety.os, "open", side_effect=guarded_open), \
                    mock.patch("builtins.open", side_effect=AssertionError("physical checks must not read content")):
                result = self.classify(path)
                self.assertEqual(result["classification"], "needs-review", result)
                self.assertTrue(any("符号链接" in e.get("reason", "") for e in result["evidence"]))
        self.assertTrue(calls, "the metadata guard must actually run")
        self.assertEqual(canary.read_text(), "must not be read")

    def test_permissions_and_non_directory_components_need_review(self):
        original_stat = os.stat
        def denied(path, *args, **kwargs):
            if os.fspath(path) == "src":
                raise PermissionError("fixture permission denied")
            return original_stat(path, *args, **kwargs)
        with mock.patch.object(safety.os, "stat", side_effect=denied):
            result = self.classify("src/a.py")
            self.assertEqual(result["classification"], "needs-review", result)
            self.assertTrue(any("permission denied" in e.get("reason", "") for e in result["evidence"]))
        self.assertEqual(self.classify("src/a.py/child")["classification"], "needs-review")

    def test_aliases_are_uncertain_without_rewriting_paths(self):
        for left, right in (("Src/a", "src/a"), ("SRC", "src/b"), ("caf\u00e9/a", "cafe\u0301/a")):
            result = self.classify(left, right)
            self.assertEqual(result["classification"], "needs-review", result)
            self.assertTrue(any(e["category"] == "path-alias" for e in result["evidence"]))
            self.assertEqual(result["pathDeclarations"]["alpha"][0]["normalized"], left)
        (self.project / "Existing").mkdir()
        result = self.classify("existing/new.py")
        self.assertEqual(result["classification"], "needs-review", result)
        self.assertTrue(any("别名" in e.get("reason", "") for e in result["evidence"]))


class ReadinessDependencyLayers(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="sg-readiness-")
        self.addCleanup(self.directory.cleanup)
        self.project = Path(self.directory.name) / "project with spaces"
        self.project.mkdir()
        (self.project / "spec").mkdir()
        (self.project / ".agent").mkdir()
        (self.project / ".agent/state.json").write_text('{"activeModule":"identity"}')
        self.path = self.project / "spec/CAPABILITY-MAP.md"
        self.path.write_text(TABLE + "\nBuild order: " + ORDER + "\n")
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.name=test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")
        self.sha = self.git("rev-parse", "HEAD")
        self.git("update-ref", "refs/remotes/origin/trunk", self.sha)
        self.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.project)] + list(args), text=True).strip()

    def run_readiness(self, output_format="json"):
        # 包含真实 refs、索引、state 和未提交图；只读分析不能修改这些文件。
        before = {str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}
        result = subprocess.run([sys.executable, str(hooks / "parallel-readiness.py"),
                                 "--project", str(self.project), "--format", output_format],
                                capture_output=True, text=True)
        self.assertEqual({str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}, before)
        return result

    def test_candidates_follow_dependencies_not_display_groups(self):
        for order, expected in ((ORDER, ["billing", "notifications"]),
                                ("identity → billing → notifications → reporting", ["billing", "notifications"]),
                                ("identity → notifications, billing → reporting", ["notifications", "billing"])):
            with self.subTest(order=order):
                self.path.write_text(TABLE + "\nBuild order: " + order + "\n")
                result = self.run_readiness()
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads(result.stdout)
                self.assertEqual(report["candidateGroups"], [{"layer": 1, "modules": expected,
                                                            "classification": "candidate-only"}])
                self.assertEqual(report["base"], {"ref": "origin/trunk", "sha": self.sha, "fresh": False})
                self.assertTrue(any("尚未验证远端新鲜度" in warning for warning in report["warnings"]))

    def test_json_and_text_do_not_claim_execution_readiness(self):
        result = self.run_readiness()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertIn("未核验任务状态", report["notice"])
        self.assertIn("不表示可立即领取或执行", report["notice"])
        text = self.run_readiness("text")
        self.assertEqual(text.returncode, 0, text.stderr)
        self.assertIn(report["notice"], text.stdout)
        self.assertIn("新鲜度: 未验证", text.stdout)

    def test_invalid_graph_fails_without_success_output(self):
        self.path.write_text(TABLE.replace("Messages | identity", "Messages | billing") +
                             "\nBuild order: " + ORDER + "\n")
        for output_format in ("json", "text"):
            result = self.run_readiness(output_format)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("parallel-readiness:", result.stderr)


class BoundaryCliDiagnostics(unittest.TestCase):
    def setUp(self):
        ReadinessDependencyLayers.setUp(self)
        self.path.write_text(TABLE + "\nBuild order: " + ORDER + "\n")

    git = ReadinessDependencyLayers.git

    def write_boundary(self, module, paths):
        data = dict({field: [] for field in FIELDS}, paths=paths)
        (self.project / "spec" / (module + ".md")).write_text(
            "## Parallel Boundary\n```json\n" + json.dumps(data) + "\n```\n")

    def run_cli(self, script, output_format):
        before = {str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}
        result = subprocess.run([sys.executable, str(hooks / script), "--project", str(self.project),
                                 "--format", output_format], capture_output=True, text=True)
        self.assertEqual({str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}, before)
        return result

    def test_both_formats_preserve_conflict_and_uncertainty(self):
        for left, right, classification, categories in ((["src/", "Src/a"], ["src/a"], "sequential-required", {"paths", "path-alias"}),
                                                        (["Src/a"], ["src/a"], "needs-review", {"path-alias"}),
                                                        (["src/a"], ["src-old/b"], "manual-parallel-eligible", set())):
            self.write_boundary("billing", left)
            self.write_boundary("notifications", right)
            for script in ("parallel-safety-gate.py", "parallel-guidance.py"):
                with self.subTest(script=script, classification=classification):
                    result = self.run_cli(script, "json")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    report = json.loads(result.stdout)
                    group = report["groups"][0]
                    self.assertEqual(group["classification"], classification)
                    self.assertEqual({e["category"] for e in group["evidence"]}, categories)
                    self.assertEqual(group["pathDeclarations"]["billing"][0]["raw"], sorted(left)[0])
                    self.assertIn("不证明物理隔离", group["scopeNotice"])
                    if script == "parallel-guidance.py":
                        self.assertEqual(len(group["workers"]), 2 if classification == "manual-parallel-eligible" else 0)
                    text = self.run_cli(script, "text")
                    self.assertEqual(text.returncode, 0, text.stderr)
                    for expected in [classification, "billing", "notifications", "不证明物理隔离", "新鲜度", "未核验任务状态"] + list(categories):
                        self.assertIn(expected, text.stdout)
                    for evidence in group["evidence"]:
                        if "reason" in evidence:
                            self.assertIn(evidence["reason"], text.stdout)
                    if classification != "manual-parallel-eligible":
                        self.assertNotIn("codex/parallel/", text.stdout)

    def test_boundary_errors_retain_specific_reason(self):
        self.write_boundary("billing", ["../outside"])
        self.write_boundary("notifications", ["src/b"])
        for script in ("parallel-safety-gate.py", "parallel-guidance.py"):
            result = self.run_cli(script, "json")
            self.assertEqual(result.returncode, 0, result.stderr)
            group = json.loads(result.stdout)["groups"][0]
            self.assertEqual(group["classification"], "needs-review")
            self.assertTrue(any("../outside" in e.get("reason", "") for e in group["evidence"]), group)
            text = self.run_cli(script, "text")
            self.assertIn("../outside", text.stdout)

    def test_bad_or_unreadable_map_has_no_success_or_traceback(self):
        for content in (b"bad map", b"\xff", None):
            if content is None:
                self.path.unlink()
            else:
                self.path.write_bytes(content)
            for script in ("parallel-safety-gate.py", "parallel-guidance.py"):
                for output_format in ("json", "text"):
                    result = self.run_cli(script, output_format)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")
                    self.assertIn(script[:-3] + ":", result.stderr)
                    self.assertNotIn("Traceback", result.stderr)


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


def selftest():
    """在隔离插件副本恢复旧漏洞；每个都必须让同一份聚焦回归变红。"""
    mutations = [
        ("不拆并列 Build order", "hooks/capability_map.py",
         'groups = [[_strip_ticks(item) for item in group.split(",")]',
         'groups = [[_strip_ticks(group)]'),
        ("同组依赖按展开位置放行", "hooks/capability_map.py",
         'positions = {module_id: index for index, group in enumerate(order_groups)\n                 for module_id in group}',
         'positions = {module_id: index for index, module_id in enumerate(order)}'),
        ("尾斜杠不规范化", "hooks/parallel_safety_gate.py",
         'return "/".join(part for part in value.split("/") if part not in ("", ".")) or "."',
         'return value'),
        ("直接库调用绕过边界验证", "hooks/parallel_safety_gate.py",
         'valid[module] = _validate_boundary(boundaries[module])',
         'valid[module] = boundaries[module]'),
        ("链接检查被绕过", "hooks/parallel_safety_gate.py",
         'if stat.S_ISLNK(metadata.st_mode):',
         'if False:'),
        ("Desktop 预览吞掉子进程失败", "mcp/claude_desktop_server.mjs",
         'if (result.status !== 0)',
         'if (false)'),
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
