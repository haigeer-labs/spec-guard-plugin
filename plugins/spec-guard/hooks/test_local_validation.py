"""Local-stage regressions: plain temporary files, stub Git/tracker CLIs only."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from local_validation import inspect_stage
from workspace_binding import BindingError, _facts


HOOKS = Path(__file__).resolve().parent
MAP = """# Capability Map: Test
## 目标
Local validation.
## 模块
| Module id | Responsibility | Depends on |
|---|---|---|
| alpha | Test local stage | — |
Build order: alpha
"""


class LocalValidationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sg-local-stage-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for path in (".agent", "spec", "tasks/alpha", "bin"):
            (self.root / path).mkdir(parents=True)
        (self.root / "spec/CAPABILITY-MAP.md").write_text(MAP)
        (self.root / "spec/alpha.md").write_text("# Alpha\n")
        (self.root / "tasks/alpha/plan.md").write_text("# Plan\nLocal scope.\n")
        self.state = {
            "tracker": "github", "workflowStage": "local-validation",
            "initiative": {"title": "Test", "issue": None, "map": "spec/CAPABILITY-MAP.md"},
            "modules": {}, "activeModule": "alpha", "issueTypes": False,
        }
        self.save()
        for tool in ("git", "gh", "glab"):
            script = self.root / "bin" / tool
            script.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$SG_TEST_CALLS"\nexit 1\n')
            script.chmod(0o700)

    def save(self):
        (self.root / ".agent/state.json").write_text(json.dumps(self.state))

    def hooks(self):
        self.save()
        env = dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root),
                   PLUGIN_ROOT=str(HOOKS.parent), PYTHONDONTWRITEBYTECODE="1",
                   PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                   SG_TEST_CALLS=str(self.root / "calls"))
        phase = subprocess.run(["/bin/bash", str(HOOKS / "phase-guard.sh")],
                               env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(phase.returncode, 0, phase.stderr)
        context = json.loads(phase.stdout)["hookSpecificOutput"]["additionalContext"]
        verify = subprocess.run(["/bin/bash", str(HOOKS / "verify-artifacts.sh")],
                                env=env, capture_output=True, text=True, timeout=10)
        calls = (self.root / "calls").read_text() if (self.root / "calls").exists() else ""
        self.assertNotIn("/bin/gh", calls)
        self.assertNotIn("/bin/glab", calls)
        self.assertFalse((self.root / ".git").exists())
        return context, verify

    def assert_invalid(self):
        self.save()
        self.assertEqual(inspect_stage(self.root)[0], "invalid")
        context, verify = self.hooks()
        self.assertIn("LOCAL_VALIDATION_INVALID", context)
        self.assertEqual(verify.returncode, 1, verify.stdout)
        self.assertIn("本地验证阶段不可用", verify.stdout)
        self.assertNotIn("/spec-guard:bind-workspace", context)

    def test_valid_trackers_and_no_remote_green(self):
        for tracker in ("github", "gitlab"):
            with self.subTest(tracker=tracker):
                self.state["tracker"] = tracker
                self.save()
                self.assertEqual(inspect_stage(self.root)[0], "valid")
                context, verify = self.hooks()
                self.assertIn("LOCAL_VALIDATION (tracker 尚未激活)", context)
                self.assertIn("活跃模块: alpha", context)
                for command in ("/spec-guard:next", "/spec-guard:deliver", "/spec-guard:bind-workspace"):
                    self.assertNotIn(command, context)
                self.assertEqual(verify.returncode, 0, verify.stdout)
                self.assertIn("tracker 尚未激活", verify.stdout)
                self.assertNotIn("binding 已验证", verify.stdout)

    def test_unknown_and_null_stage(self):
        for value in ("building", "", None, [], True):
            with self.subTest(value=value):
                self.state["workflowStage"] = value
                self.assert_invalid()

    def test_issue_mapping_cannot_be_disguised(self):
        for update in ({"initiative": {"title": "Test", "issue": 7, "map": "spec/CAPABILITY-MAP.md"}},
                       {"modules": {"alpha": {"issue": 8}}}):
            original = copy.deepcopy(self.state)
            self.state.update(update)
            self.assert_invalid()
            self.state = original

    def test_bad_module_and_tracker(self):
        for field, value in (("activeModule", []), ("activeModule", ""),
                             ("activeModule", "missing"), ("activeModule", "../alpha"),
                             ("tracker", "none"), ("issueTypes", "false")):
            original = copy.deepcopy(self.state)
            with self.subTest(field=field, value=value):
                self.state[field] = value
                self.assert_invalid()
            self.state = original

    def test_missing_spec_or_plan(self):
        for name in ("spec/alpha.md", "tasks/alpha/plan.md"):
            path = self.root / name
            contents = path.read_text()
            path.unlink()
            self.assert_invalid()
            path.write_text(contents)

    def test_invalid_map(self):
        (self.root / "spec/CAPABILITY-MAP.md").write_text("# No graph\n")
        self.assert_invalid()

    def test_invalid_initiative(self):
        for value in ({}, {"title": "", "issue": None}, None):
            self.state["initiative"] = value
            self.assert_invalid()

    def test_absent_stage_preserves_missing_issue_gate(self):
        del self.state["workflowStage"]
        self.save()
        self.assertEqual(inspect_stage(self.root)[0], "absent")
        # Legacy verification may call gh; stub still prevents any remote operation.
        env = dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root), PLUGIN_ROOT=str(HOOKS.parent),
                   PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                   SG_TEST_CALLS=str(self.root / "calls"), PYTHONDONTWRITEBYTECODE="1")
        phase = subprocess.run(["/bin/bash", str(HOOKS / "phase-guard.sh")],
                               env=env, capture_output=True, text=True, timeout=10)
        self.assertNotIn("LOCAL_VALIDATION", phase.stdout)
        self.assertIn("SPECED", phase.stdout)
        verify = subprocess.run(["/bin/bash", str(HOOKS / "verify-artifacts.sh")],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(verify.returncode, 1, verify.stdout)
        self.assertIn("binding 不可用", verify.stdout)

    def test_absent_state(self):
        (self.root / ".agent/state.json").unlink()
        self.assertEqual(inspect_stage(self.root)[0], "absent")

    def test_malformed_state_is_not_idle(self):
        for contents in ("{", "[]", "null"):
            (self.root / ".agent/state.json").write_text(contents)
            self.assertEqual(inspect_stage(self.root)[0], "invalid")

    def test_valid_stage_does_not_hide_artifact_violations(self):
        for path, contents, expected in (
                ("spec/orphan.md", "# Orphan\n", "能力图上没有的模块"),
                ("tasks/alpha/plan.md", "# Plan\n- [ ] Task\n", "里有 checkbox")):
            target = self.root / path
            target.write_text(contents)
            context, verify = self.hooks()
            self.assertIn("LOCAL_VALIDATION (tracker 尚未激活)", context)
            self.assertEqual(verify.returncode, 1, verify.stdout)
            self.assertIn(expected, verify.stdout)
            target.unlink()

    def test_binding_rejects_stage_even_with_real_looking_mappings(self):
        self.state["initiative"]["issue"] = 7
        self.state["modules"] = {"alpha": {"issue": 8}}
        self.save()
        with self.assertRaisesRegex(BindingError, "workflowStage"):
            _facts(self.root, self.root / "spec/CAPABILITY-MAP.md", self.root / ".agent/state.json")


if __name__ == "__main__":
    unittest.main()
