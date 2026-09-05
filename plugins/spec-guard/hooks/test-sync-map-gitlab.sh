#!/usr/bin/env bash
# GitLab map 投影的可恢复、幂等回归；全部使用离线 glab 端点桩。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

root = Path(sys.argv[1])
sys.argv[:] = [sys.argv[0]]
hooks = root / "hooks"

MAP = """# Capability Map: Ordered GitLab Sync

## 目标

验证可恢复 state 写回。

## 模块

| Module id | Responsibility | Depends on |
| --- | --- | --- |
| second | 第二个模块 | first |
| first | 第一个模块 | — |

Build order: first → second

---

## 评审记录

- [x] 模块边界确认
- [x] 依赖方向单向无环
- [x] module id 已定稿
- [x] 构建顺序符合依赖拓扑
"""


class SyncMapGitLab(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sg-gitlab-sync-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.project = self.work / "project"
        (self.project / ".agent").mkdir(parents=True)
        (self.project / "spec").mkdir()
        subprocess.run(["git", "init", "-q", str(self.project)], check=True)
        (self.project / "spec/CAPABILITY-MAP.md").write_text(MAP, encoding="utf-8")
        self.state = self.project / ".agent/state.json"
        self.write_state({"tracker": "gitlab", "initiative": {"title": "", "issue": None,
                          "map": "spec/CAPABILITY-MAP.md"}, "issueTypes": False,
                          "modules": {}, "activeModule": "", "updatedAt": ""})
        self.db = self.work / "glab-db.json"
        self.db.write_text(json.dumps({"issues": [], "postCount": 0, "dropUsed": False}), encoding="utf-8")
        self.bin = self.work / "bin"
        self.bin.mkdir()
        stub = self.bin / "glab"
        stub.write_text("#!" + sys.executable + "\n" + r'''
import json, os, pathlib, sys
args = sys.argv[1:]
db_path = pathlib.Path(os.environ["GLAB_DB"])
db = json.loads(db_path.read_text())

def save():
    db_path.write_text(json.dumps(db))

if args == ["auth", "status"]:
    raise SystemExit(0)
if args == ["repo", "view", "--output", "json"]:
    print(json.dumps({"path_with_namespace": "test/project"}))
    raise SystemExit(0)
if not args or args[0] != "api":
    raise SystemExit("unexpected glab invocation: " + repr(args))
if "projects/test%2Fproject" in args:
    print(json.dumps({"id": 17}))
    raise SystemExit(0)
post = "-X" in args and "POST" in args
endpoint = next((arg for arg in args if arg.startswith("projects/17/issues")), "")
if post and endpoint == "projects/17/issues":
    title = next(arg[6:] for arg in args if arg.startswith("title="))
    description = next(arg[12:] for arg in args if arg.startswith("description="))
    iid = len(db["issues"]) + 1
    issue = {"iid": iid, "project_id": 17, "title": title, "description": description,
             "state": "opened"}
    db["issues"].append(issue)
    db["postCount"] += 1
    should_drop = os.environ.get("GLAB_DROP_ONCE") == "1" and not db.get("dropUsed")
    db["dropUsed"] = db.get("dropUsed") or should_drop
    save()
    if should_drop:
        raise SystemExit(1)
    print(json.dumps(issue))
    raise SystemExit(0)
if endpoint.startswith("projects/17/issues?"):
    print(json.dumps(db["issues"]))
    raise SystemExit(0)
if endpoint.startswith("projects/17/issues/"):
    iid = int(endpoint.rsplit("/", 1)[1])
    for issue in db["issues"]:
        if issue["iid"] == iid:
            print(json.dumps(issue))
            raise SystemExit(0)
    raise SystemExit(1)
raise SystemExit("unexpected GitLab API endpoint: " + repr(args))
''', encoding="utf-8")
        stub.chmod(0o755)

    def write_state(self, value):
        self.state.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def read_db(self):
        return json.loads(self.db.read_text(encoding="utf-8"))

    def run_sync(self, *args, drop=False):
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                   CLAUDE_PROJECT_DIR=str(self.project), GLAB_DB=str(self.db))
        if drop:
            env["GLAB_DROP_ONCE"] = "1"
        return subprocess.run(["/bin/bash", str(hooks / "sync-map-gitlab.sh"), *args],
                              env=env, capture_output=True, text=True)

    def digest(self):
        result = subprocess.run([sys.executable, str(hooks / "spec-digest.py"), "compute",
                                 str(self.project / "spec/CAPABILITY-MAP.md")],
                                capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_preview_is_read_only(self):
        before = self.state.read_bytes()
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("first", result.stdout)
        self.assertEqual(self.read_db()["postCount"], 0)
        self.assertEqual(self.state.read_bytes(), before)

    def test_repeat_reuses_verified_projection_and_digests(self):
        first = self.run_sync("--confirm")
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        initial = self.state.read_bytes()
        state = json.loads(initial)
        digest = self.digest()
        self.assertEqual(self.read_db()["postCount"], 3)
        self.assertEqual(state["initiative"]["goalDigest"], digest["goalDigest"])
        self.assertEqual(state["modules"]["first"]["rowDigest"], digest["rows"][1]["rowDigest"])
        second = self.run_sync("--confirm")
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(self.read_db()["postCount"], 3)
        self.assertEqual(self.state.read_bytes(), initial)

    def test_lost_create_response_recovers_unique_marker(self):
        result = self.run_sync("--confirm", drop=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        state = json.loads(self.state.read_text(encoding="utf-8"))
        self.assertEqual(self.read_db()["postCount"], 3)
        self.assertEqual(state["initiative"]["issue"], 1)
        self.assertEqual(set(state["modules"]), {"first", "second"})

    def test_atomic_state_write_never_reuses_a_predictable_temp_name(self):
        sentinel = self.state.with_name(".state.json.spec-guard-tmp")
        sentinel.write_text("do not overwrite", encoding="utf-8")
        result = self.run_sync("--confirm")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "do not overwrite")

    def test_stale_state_stops_without_post_or_overwrite(self):
        self.write_state({"tracker": "gitlab", "initiative": {"title": "old", "issue": 99,
                          "map": "spec/CAPABILITY-MAP.md", "goalDigest": "a1b2c3d4e5f6"},
                          "issueTypes": False, "modules": {}, "activeModule": "", "updatedAt": "old"})
        before = self.state.read_bytes()
        result = self.run_sync("--confirm")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read_db()["postCount"], 0)
        self.assertEqual(self.state.read_bytes(), before)

    def test_ambiguous_marker_stops_without_post_or_overwrite(self):
        digest = self.digest()
        marker = "<!-- spec-guard-sync:v2 kind=initiative goalDigest=%s -->" % digest["goalDigest"]
        self.db.write_text(json.dumps({"postCount": 0, "dropUsed": False, "issues": [
            {"iid": 1, "project_id": 17, "title": "one", "description": marker},
            {"iid": 2, "project_id": 17, "title": "two", "description": marker},
        ]}), encoding="utf-8")
        before = self.state.read_bytes()
        result = self.run_sync("--confirm")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read_db()["postCount"], 0)
        self.assertEqual(self.state.read_bytes(), before)


if __name__ == "__main__":
    result = unittest.main(verbosity=2, exit=False).result
    raise SystemExit(not result.wasSuccessful())
PY
