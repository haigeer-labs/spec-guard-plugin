"""Read-only roadmap facts must remain conservative when evidence is missing."""
import json
import io
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import patch

from workflow_roadmap import collect, main, render


MAP = """# Capability Map: Test roadmap

## 目标

Make the workflow visible.

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| foundation | Establish shared facts | — |
| current-work | Render a roadmap | foundation |
| follow-up | Consume the route | current-work |

Build order: foundation → current-work → follow-up
"""


class WorkflowRoadmapTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sg-roadmap-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for path in (".agent", "spec", "tasks/current-work"):
            (self.root / path).mkdir(parents=True, exist_ok=True)
        (self.root / "spec/CAPABILITY-MAP.md").write_text(MAP, encoding="utf-8")
        (self.root / "spec/current-work.md").write_text("# Spec: current-work\n", encoding="utf-8")
        (self.root / "tasks/current-work/plan.md").write_text(
            "# Plan\n\n## Checkpoint: After facts\n- [ ] Review the output\n\n"
            "**Next step:** Review the output.\n", encoding="utf-8")
        (self.root / ".agent/state.json").write_text(json.dumps({
            "tracker": "github", "issueTypes": False, "modules": {},
            "activeModule": "current-work", "workflowStage": "local-validation",
            "initiative": {"title": "Test roadmap", "issue": None,
                           "map": "spec/CAPABILITY-MAP.md"},
        }), encoding="utf-8")

    def test_local_stage_keeps_route_local_and_preserves_graph_edges(self):
        facts = collect(self.root)
        self.assertTrue(facts["ok"])
        self.assertEqual(facts["currentModule"], "current-work")
        self.assertEqual(facts["dependencies"], ["foundation"])
        self.assertEqual(facts["successors"], ["follow-up"])
        self.assertEqual(facts["mode"], "local-validation")
        self.assertEqual(facts["remote"], "not-applicable")
        self.assertEqual(facts["checkpoint"]["name"], "After facts")
        self.assertEqual(facts["nextAction"]["detail"], "Review the output.")
        output = render(facts)
        self.assertIn("正常工作流（agent-skills）", output)
        self.assertIn("当前模块: current-work", output)
        self.assertIn("模块链路位置", output)
        self.assertIn("下一行动（不等于检查点）", output)
        self.assertIn("路线图只提供导航", output)
        self.assertIn("远端任务、同步和交付均不适用", output)
        self.assertNotIn("百分比", output)

    def test_missing_or_invalid_identity_never_infers_current_module(self):
        (self.root / ".agent/state.json").write_text("{}", encoding="utf-8")
        facts = collect(self.root)
        self.assertFalse(facts["ok"])
        self.assertIsNone(facts["currentModule"])
        self.assertIn("initiative", facts["problems"][0])

    def test_missing_module_artifact_keeps_identity_but_marks_a_chain_break(self):
        (self.root / "tasks/current-work/plan.md").unlink()
        facts = collect(self.root)
        self.assertTrue(facts["ok"])
        self.assertEqual(facts["currentModule"], "current-work")
        self.assertFalse(facts["planExists"])
        self.assertEqual(facts["nextAction"]["evidence"], "?")
        self.assertTrue(any("当前模块缺少 Plan" in problem for problem in facts["problems"]))
        output = render(facts)
        self.assertIn("当前位置", output)
        self.assertIn("Plan（! 产物缺失）", output)

    def test_all_view_is_limited_to_the_active_map(self):
        facts = collect(self.root)
        output = render(facts, all_modules=True)
        self.assertIn("foundation", output)
        self.assertIn("current-work", output)
        self.assertIn("follow-up", output)
        self.assertNotIn("history", output.lower())

    def test_activated_tracker_without_a_safe_remote_fact_stays_unknown(self):
        state_path = self.root / ".agent/state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        del state["workflowStage"]
        state["tracker"] = "gitlab"
        state["modules"] = {"current-work": {"issue": 41}}
        state["initiative"]["issue"] = 40
        state_path.write_text(json.dumps(state), encoding="utf-8")
        facts = collect(self.root)
        self.assertTrue(facts["ok"])
        self.assertEqual(facts["remote"], "unknown")
        self.assertIn("远端事实: 未知", render(facts))

    def test_github_refresh_is_read_only_and_marks_verified_facts(self):
        state_path = self.root / ".agent/state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        del state["workflowStage"]
        state["modules"] = {"current-work": {"issue": 41}}
        state["initiative"]["issue"] = 40
        state_path.write_text(json.dumps(state), encoding="utf-8")
        reply = SimpleNamespace(returncode=0, stdout=json.dumps({
            "state": "OPEN", "subIssues": {"totalCount": 2},
        }), stderr="")
        with patch("workflow_roadmap._run_remote", return_value=reply) as remote:
            facts = collect(self.root)
        self.assertEqual(facts["remote"], "verified")
        self.assertIn("Issue #41", facts["remoteDetail"])
        self.assertIn("Issue #41", render(facts))
        commands = [call.args[0] for call in remote.call_args_list]
        self.assertIn(["gh", "issue", "view", "41", "--json", "state,subIssues"], commands)

    def test_github_auth_failure_explains_credential_access_without_guessing_state(self):
        state_path = self.root / ".agent/state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        del state["workflowStage"]
        state["modules"] = {"current-work": {"issue": 41}}
        state["initiative"]["issue"] = 40
        state_path.write_text(json.dumps(state), encoding="utf-8")
        reply = SimpleNamespace(returncode=1, stdout="", stderr=(
            "Failed to log in to github.com account haigeermail\n"
            "The token in default is invalid."
        ))
        with patch("workflow_roadmap._run_remote", return_value=reply):
            facts = collect(self.root)
        self.assertEqual(facts["remote"], "unknown")
        self.assertIn("认证或凭据访问不可用", facts["remoteDetail"])
        self.assertIn("gh auth status", facts["remoteDetail"])
        self.assertNotIn("Keychain", facts["remoteDetail"])

    def test_github_network_failure_explains_remote_query_cannot_reach_api(self):
        state_path = self.root / ".agent/state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        del state["workflowStage"]
        state["modules"] = {"current-work": {"issue": 41}}
        state_path.write_text(json.dumps(state), encoding="utf-8")
        reply = SimpleNamespace(returncode=1, stdout="", stderr=(
            "error connecting to api.github.com\n"
            "check your internet connection or https://githubstatus.com\n"
        ))
        with patch("workflow_roadmap._run_remote", return_value=reply):
            facts = collect(self.root)
        self.assertEqual(facts["remote"], "unknown")
        self.assertIn("GitHub API 网络访问不可用", facts["remoteDetail"])

    def test_malformed_tracker_mapping_degrades_without_a_traceback(self):
        state_path = self.root / ".agent/state.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        del state["workflowStage"]
        state["modules"] = []
        state_path.write_text(json.dumps(state), encoding="utf-8")
        facts = collect(self.root)
        self.assertTrue(facts["ok"])
        self.assertEqual(facts["remote"], "unknown")
        self.assertIn("远端事实: 未知", render(facts))

    def test_cli_prints_the_same_read_only_route(self):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(main(["--project", str(self.root), "--all"]), 0)
        self.assertIn("活跃能力图模块（--all）", stdout.getvalue())

    def test_chinese_declared_next_step_is_navigation_not_permission(self):
        plan = self.root / "tasks/current-work/plan.md"
        plan.write_text("# Plan\n\n**下一步：** 检查本地 diff。\n", encoding="utf-8")
        facts = collect(self.root)
        self.assertEqual(facts["nextAction"]["detail"], "检查本地 diff。")
        self.assertIn("不授予本地修改", render(facts))

    def test_roadmap_command_preflights_github_auth_without_relative_checkpoint_link(self):
        command = Path(__file__).resolve().parents[1] / "commands/roadmap.md"
        text = command.read_text(encoding="utf-8")
        self.assertIn("gh auth status --hostname github.com", text)
        self.assertIn("${CLAUDE_PLUGIN_ROOT}/references/workflow-checkpoints.md", text)
        self.assertNotIn("](../references/workflow-checkpoints.md)", text)
        self.assertIn("网络不可用", text)


if __name__ == "__main__":
    unittest.main()
