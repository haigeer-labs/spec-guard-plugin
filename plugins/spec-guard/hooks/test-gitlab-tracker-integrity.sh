#!/usr/bin/env bash
# 覆盖 GitLab tracker 投影身份的严格、无写入基础契约。
set -euo pipefail

HOOKS="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-}"
case "$MODE" in
  ""|--selftest) ;;
  *) printf 'usage: %s [--selftest]\n' "$0" >&2; exit 2 ;;
esac

PYTHONDONTWRITEBYTECODE=1 python3 - "$HOOKS" "$MODE" <<'PY'
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

hooks = Path(sys.argv[1])
mode = sys.argv[2]
sys.path.insert(0, str(hooks))

from gitlab_tracker import (  # RED: the shared identity module does not exist yet.
    TrackerIdentityError,
    initiative_marker,
    module_marker,
    parse_issue_page,
    recover_exact_issue,
    select_task_candidate,
    task_marker,
)
from workspace_binding import bind_workspace, inspect_workspace, set_task_binding


GOAL = "a1b2c3d4e5f6"
ROW = "0123456789ab"


class ProjectionIdentityContract(unittest.TestCase):
    def issue(self, iid, marker, project_id=17, title="untrusted title"):
        return {"iid": iid, "project_id": project_id, "title": title,
                "description": "summary\n\n%s\n" % marker}

    def test_marker_format_is_exact_and_input_is_strict(self):
        self.assertEqual(initiative_marker(GOAL),
                         "<!-- spec-guard-sync:v2 kind=initiative goalDigest=%s -->" % GOAL)
        self.assertEqual(module_marker("audit-tracker-integrity", ROW),
                         "<!-- spec-guard-sync:v2 kind=module id=audit-tracker-integrity rowDigest=%s -->" % ROW)
        for bad in ("", "short", "A1B2C3D4E5F6", "g" * 12):
            with self.subTest(bad=bad):
                with self.assertRaises(TrackerIdentityError):
                    initiative_marker(bad)

    def test_unique_complete_marker_recovers_exact_issue(self):
        marker = initiative_marker(GOAL)
        page = parse_issue_page(json.dumps([self.issue(7, marker)]))
        found = recover_exact_issue(page, marker, project_id=17, page_complete=True)
        self.assertEqual(found["iid"], 7)

    def test_title_or_partial_marker_never_recovers_identity(self):
        marker = initiative_marker(GOAL)
        partial = "<!-- spec-guard-sync:v2 kind=initiative goalDigest=%s" % GOAL
        page = parse_issue_page(json.dumps([
            self.issue(7, partial, title="same title"),
            {"iid": 8, "project_id": 17, "title": marker, "description": "plain text"},
        ]))
        self.assertIsNone(recover_exact_issue(page, marker, project_id=17, page_complete=True))

    def test_issue_without_description_is_an_unmatched_candidate(self):
        marker = initiative_marker(GOAL)
        page = parse_issue_page(json.dumps([
            {"iid": 7, "project_id": 17, "title": "title-only", "description": None},
        ]))
        self.assertIsNone(recover_exact_issue(page, marker, project_id=17, page_complete=True))

    def test_multiple_or_incomplete_candidates_fail_closed(self):
        marker = initiative_marker(GOAL)
        page = parse_issue_page(json.dumps([self.issue(7, marker), self.issue(8, marker)]))
        with self.assertRaises(TrackerIdentityError):
            recover_exact_issue(page, marker, project_id=17, page_complete=True)
        with self.assertRaises(TrackerIdentityError):
            recover_exact_issue([self.issue(7, marker)], marker, project_id=17, page_complete=False)

    def test_invalid_json_and_foreign_marker_response_fail_closed(self):
        with self.assertRaises(TrackerIdentityError):
            parse_issue_page("{not json")
        marker = initiative_marker(GOAL)
        page = parse_issue_page(json.dumps([self.issue(7, marker, project_id=99)]))
        with self.assertRaises(TrackerIdentityError):
            recover_exact_issue(page, marker, project_id=17, page_complete=True)


class WorkspaceBindingContract(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name) / "source"
        self.worktree = Path(self.tempdir.name) / "linked"
        self.root.mkdir()
        self.git(self.root, "init", "-q")
        self.git(self.root, "config", "user.email", "test@example.invalid")
        self.git(self.root, "config", "user.name", "Spec Guard test")
        (self.root / "README.md").write_text("fixture\n", encoding="utf-8")
        self.git(self.root, "add", "README.md")
        self.git(self.root, "commit", "-qm", "bootstrap")
        (self.root / "README.md").write_text("fixture\ncompleted alpha\n", encoding="utf-8")
        self.git(self.root, "add", "README.md")
        self.git(self.root, "commit", "-qm", "complete alpha\n\nCloses #11")
        self.git(self.root, "remote", "add", "origin", "git@GitHub.com:Acme/Widget.git")
        self.git(self.root, "worktree", "add", "-q", "-b", "fixture-linked", str(self.worktree))
        self.map_path = self.root / "spec" / "CAPABILITY-MAP.md"
        self.map_path.parent.mkdir()
        self.map_path.write_text(
            "## Goal\n\nBinding fixture.\n\n"
            "| Module id | Responsibility | Depends on |\n"
            "|---|---|---|\n"
            "| alpha | foundation | — |\n"
            "| beta | dependent | alpha |\n\n"
            "Build order: alpha → beta\n",
            encoding="utf-8",
        )
        self.state_path = self.root / ".agent" / "state.json"
        self.state_path.parent.mkdir()
        self.state_path.write_text(json.dumps({
            "tracker": "github",
            "activeModule": "alpha",
            "initiative": {"issue": 10, "goalDigest": GOAL},
            "modules": {
                "alpha": {"issue": 11, "rowDigest": ROW},
                "beta": {"issue": 12, "rowDigest": ROW},
            },
        }), encoding="utf-8")

    def tearDown(self):
        self.tempdir.cleanup()

    def git(self, project, *args):
        completed = subprocess.run(["git", "-C", str(project), *args], check=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return completed.stdout.strip()

    def binding_path(self, project):
        git_dir = self.git(project, "rev-parse", "--git-dir")
        return (Path(project) / git_dir / "spec-guard" / "workspace-binding.json").resolve()

    def test_explicit_bind_is_worktree_local_and_deterministic(self):
        completed = subprocess.run([
            sys.executable, str(hooks / "workspace_binding.py"), "bind",
            "--project", str(self.root), "--map", str(self.map_path), "--state", str(self.state_path),
            "--module", "alpha", "--format", "json",
        ], check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertTrue(result["ok"])
        self.assertEqual(result["binding"]["repo"], "github.com/acme/widget")
        self.assertEqual(result["binding"]["moduleIssue"], 11)
        self.assertTrue(self.binding_path(self.root).is_file())
        self.assertEqual(inspect_workspace(str(self.root), str(self.map_path), str(self.state_path))["code"], "ok")

        linked = bind_workspace(str(self.worktree), str(self.map_path), str(self.state_path), "beta")
        self.assertTrue(linked["ok"])
        self.assertNotEqual(linked["binding"]["gitDir"], result["binding"]["gitDir"])
        self.assertEqual(inspect_workspace(str(self.worktree), str(self.map_path), str(self.state_path))["code"], "ok")

    def test_task_binding_requires_a_verified_expected_previous_value(self):
        self.assertTrue(bind_workspace(str(self.root), str(self.map_path), str(self.state_path), "alpha")["ok"])
        updated = set_task_binding(str(self.root), str(self.map_path), str(self.state_path), 21,
                                   expected_previous=None)
        self.assertTrue(updated["ok"])
        self.assertEqual(updated["binding"]["taskIssue"], 21)
        conflict = set_task_binding(str(self.root), str(self.map_path), str(self.state_path), 22,
                                    expected_previous=None)
        self.assertFalse(conflict["ok"])
        self.assertEqual(conflict["code"], "context-mismatch")

    def test_copied_or_mapped_binding_fails_closed(self):
        bound = bind_workspace(str(self.root), str(self.map_path), str(self.state_path), "alpha")
        self.assertTrue(bound["ok"])
        target = self.binding_path(self.worktree)
        target.parent.mkdir(parents=True)
        shutil.copyfile(self.binding_path(self.root), target)
        self.assertEqual(inspect_workspace(str(self.worktree), str(self.map_path), str(self.state_path))["code"],
                         "context-mismatch")

        record = json.loads(self.binding_path(self.root).read_text(encoding="utf-8"))
        record["repo"] = "github.com/acme/other"
        self.binding_path(self.root).write_text(json.dumps(record), encoding="utf-8")
        self.assertEqual(inspect_workspace(str(self.root), str(self.map_path), str(self.state_path))["code"],
                         "context-mismatch")
        record["repo"] = "github.com/acme/widget"
        record["tracker"] = "gitlab"
        self.binding_path(self.root).write_text(json.dumps(record), encoding="utf-8")
        self.assertEqual(inspect_workspace(str(self.root), str(self.map_path), str(self.state_path))["code"],
                         "context-mismatch")
        record["tracker"] = "github"
        record["moduleIssue"] = 999
        self.binding_path(self.root).write_text(json.dumps(record), encoding="utf-8")
        self.assertEqual(inspect_workspace(str(self.root), str(self.map_path), str(self.state_path))["code"],
                         "context-mismatch")

    def test_missing_bad_non_git_and_unresolved_dependency_are_not_safe(self):
        self.assertEqual(inspect_workspace(str(self.root), str(self.map_path), str(self.state_path))["code"],
                         "context-unknown")
        self.binding_path(self.root).parent.mkdir(parents=True)
        self.binding_path(self.root).write_text("{bad", encoding="utf-8")
        self.assertEqual(inspect_workspace(str(self.root), str(self.map_path), str(self.state_path))["code"],
                         "context-unknown")
        self.binding_path(self.root).write_text("[]", encoding="utf-8")
        self.assertEqual(inspect_workspace(str(self.root), str(self.map_path), str(self.state_path))["code"],
                         "context-unknown")
        self.assertEqual(inspect_workspace(self.tempdir.name, str(self.map_path), str(self.state_path))["code"],
                         "context-unknown")

        root_beta = bind_workspace(str(self.root), str(self.map_path), str(self.state_path), "beta")
        self.assertFalse(root_beta["ok"])
        self.assertEqual(root_beta["code"], "context-mismatch")

        # A dependency Issue mapped in state but without a current-HEAD closing
        # commit is not enough evidence to bind a non-default worktree module.
        self.git(self.worktree, "reset", "--hard", "HEAD~1")
        blocked = bind_workspace(str(self.worktree), str(self.map_path), str(self.state_path), "beta")
        self.assertFalse(blocked["ok"])
        self.assertEqual(blocked["code"], "dependency-blocked")


class GitLabTaskSelectionContract(unittest.TestCase):
    def issue(self, iid, state="opened", assignees=None, marker=None):
        return {
            "iid": iid, "project_id": 17, "state": state,
            "description": "task\n%s\n" % (marker or task_marker("alpha")),
            "assignees": assignees if assignees is not None else [],
        }

    def binding(self, task=None):
        return {"moduleId": "alpha", "taskIssue": task}

    def test_selects_only_exact_open_plan_indexed_task_in_order(self):
        result = select_task_candidate(self.binding(), [12, 13], {
            12: self.issue(12, state="closed"),
            13: self.issue(13),
        }, project_id=17, current_user="me", closed_by_commit=set())
        self.assertEqual(result, {"ok": True, "code": "ok", "taskIssue": 13})

    def test_rejects_foreign_marker_assignee_and_closing_commit(self):
        result = select_task_candidate(self.binding(), [12, 13, 14, 15], {
            12: self.issue(12, state="closed"),
            13: self.issue(13, assignees=[{"username": "other"}]),
            14: self.issue(14),
            15: self.issue(15),
        }, project_id=17, current_user="me", closed_by_commit={14})
        self.assertEqual(result, {"ok": True, "code": "ok", "taskIssue": 15})

    def test_unfinished_local_binding_returns_it_and_unknown_facts_fail_closed(self):
        existing = select_task_candidate(self.binding(13), [12, 13], {
            12: self.issue(12), 13: self.issue(13),
        }, project_id=17, current_user="me", closed_by_commit=set())
        self.assertEqual(existing, {"ok": True, "code": "task-in-progress", "taskIssue": 13})
        broken = select_task_candidate(self.binding(), [12], {
            12: {"iid": 12, "project_id": 17, "state": "opened", "description": task_marker("alpha")},
        }, project_id=17, current_user="me", closed_by_commit=set())
        self.assertFalse(broken["ok"])
        self.assertEqual(broken["code"], "context-unknown")
        mismatch = select_task_candidate(self.binding(), [12], {
            12: self.issue(12, marker="<!-- spec-guard-task:module=other -->"),
        }, project_id=17, current_user="me", closed_by_commit=set())
        self.assertFalse(mismatch["ok"])
        self.assertEqual(mismatch["code"], "context-mismatch")


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if mode == "--selftest" and result.wasSuccessful():
        print("selftest: title-only and partial-marker recovery are rejected")
    raise SystemExit(not result.wasSuccessful())
PY
