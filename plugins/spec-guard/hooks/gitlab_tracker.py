"""GitLab 能力图投影的严格身份基元。

恢复只能基于完整、版本化 marker；标题和部分文本只是搜索候选，不能建立身份。
本模块不执行 glab、文件或 tracker 写入，供同步器和后续任务选择器共享。
"""
from __future__ import print_function

import argparse
import datetime
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote, urlencode


DIGEST = re.compile(r"^[0-9a-f]{12}$")
MODULE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class TrackerIdentityError(ValueError):
    """远端投影身份无法可靠判定时的可诊断错误。"""


def _digest(value, field):
    if not isinstance(value, str) or not DIGEST.fullmatch(value):
        raise TrackerIdentityError("%s 必须是 12 位小写十六进制 digest" % field)
    return value


def initiative_marker(goal_digest):
    """返回 initiative 投影的唯一、可恢复 marker。"""
    return "<!-- spec-guard-sync:v2 kind=initiative goalDigest=%s -->" % _digest(
        goal_digest, "goalDigest")


def module_marker(module_id, row_digest):
    """返回模块投影的唯一、可恢复 marker。"""
    if not isinstance(module_id, str) or not MODULE_ID.fullmatch(module_id):
        raise TrackerIdentityError("module id 必须是 kebab-case")
    return "<!-- spec-guard-sync:v2 kind=module id=%s rowDigest=%s -->" % (
        module_id, _digest(row_digest, "rowDigest"))


def task_marker(module_id):
    """返回 plan-indexed GitLab task 必须逐行携带的模块身份 marker。"""
    if not isinstance(module_id, str) or not MODULE_ID.fullmatch(module_id):
        raise TrackerIdentityError("module id 必须是 kebab-case")
    return "<!-- spec-guard-task:module=%s -->" % module_id


def _task_identity(issue, module_id, project_id):
    if not isinstance(issue, dict):
        return reject_task("context-unknown", "GitLab task 响应不是对象")
    if issue.get("project_id") != project_id:
        return reject_task("context-mismatch", "GitLab task 不属于当前项目")
    if not isinstance(issue.get("iid"), int) or issue["iid"] <= 0:
        return reject_task("context-unknown", "GitLab task 缺少有效 iid")
    if issue.get("state") not in ("opened", "closed"):
        return reject_task("context-unknown", "GitLab task state 不可读取")
    if not isinstance(issue.get("description"), str):
        return reject_task("context-unknown", "GitLab task 缺少 description")
    if task_marker(module_id) not in issue["description"].splitlines():
        return reject_task("context-mismatch", "GitLab task 缺少当前模块的完整 marker")
    assignees = issue.get("assignees")
    if not isinstance(assignees, list):
        return reject_task("context-unknown", "GitLab task assignees 不可读取")
    names = []
    for assignee in assignees:
        name = assignee.get("username") if isinstance(assignee, dict) else None
        if not isinstance(name, str) or not name:
            return reject_task("context-unknown", "GitLab task assignee 不可读取")
        names.append(name)
    return {"ok": True, "issue": issue, "assignees": names}


def reject_task(code, message):
    return {"ok": False, "code": code, "message": message}


def select_task_candidate(binding, plan_iids, issues, project_id, current_user, closed_by_commit):
    """从已读取的 GitLab task facts 中确定唯一下一项，绝不查询或写入 tracker。"""
    if (not isinstance(binding, dict) or not isinstance(binding.get("moduleId"), str) or
            binding.get("taskIssue") is not None and
            (type(binding["taskIssue"]) is not int or binding["taskIssue"] <= 0)):
        return reject_task("context-unknown", "worktree binding 缺少有效模块或 task")
    if (not isinstance(plan_iids, list) or not plan_iids or
            any(type(iid) is not int or iid <= 0 for iid in plan_iids) or
            len(set(plan_iids)) != len(plan_iids) or not isinstance(issues, dict) or
            type(project_id) is not int or project_id <= 0 or
            not isinstance(current_user, str) or not current_user or
            not isinstance(closed_by_commit, set) or
            any(type(iid) is not int or iid <= 0 for iid in closed_by_commit)):
        return reject_task("context-unknown", "GitLab task 选择输入不完整")

    ordered = ([binding["taskIssue"]] if binding["taskIssue"] is not None else []) + [
        iid for iid in plan_iids if iid != binding.get("taskIssue")]
    for iid in ordered:
        if iid not in plan_iids:
            return reject_task("context-mismatch", "binding task 不属于当前模块计划索引")
        checked = _task_identity(issues.get(iid), binding["moduleId"], project_id)
        if not checked["ok"]:
            return checked
        issue = checked["issue"]
        if issue["state"] == "closed" or iid in closed_by_commit:
            continue
        if any(name != current_user for name in checked["assignees"]):
            continue
        if binding.get("taskIssue") == iid:
            return {"ok": True, "code": "task-in-progress", "taskIssue": iid}
        return {"ok": True, "code": "ok", "taskIssue": iid}
    return {"ok": True, "code": "no-eligible-task", "taskIssue": None}


def parse_issue_page(payload):
    """严格读取 GitLab Issues API 的一页 JSON 响应。"""
    try:
        page = json.loads(payload)
    except (TypeError, ValueError) as error:
        raise TrackerIdentityError("GitLab Issue 列表不是合法 JSON") from error
    if not isinstance(page, list):
        raise TrackerIdentityError("GitLab Issue 列表必须是数组")
    for issue in page:
        if (not isinstance(issue, dict) or
                not isinstance(issue.get("iid"), int) or issue["iid"] <= 0 or
                not isinstance(issue.get("project_id"), int) or issue["project_id"] <= 0 or
                not isinstance(issue.get("description"), (str, type(None)))):
            raise TrackerIdentityError("GitLab Issue 响应缺少可验证的 iid/project_id/description")
    return page


def recover_exact_issue(page, marker, project_id, page_complete):
    """从完整页中恢复唯一完整 marker 对应的 Issue，不能判定就拒绝。"""
    if page_complete is not True:
        raise TrackerIdentityError("GitLab 搜索结果页不完整，不能安全恢复投影")
    if not isinstance(project_id, int) or project_id <= 0:
        raise TrackerIdentityError("project_id 必须是正整数")
    if not isinstance(marker, str) or not marker.startswith("<!-- spec-guard-sync:v2 "):
        raise TrackerIdentityError("marker 不是受支持的 spec-guard v2 标记")

    matches = []
    for issue in page:
        if not isinstance(issue, dict):
            raise TrackerIdentityError("GitLab Issue 响应不是对象")
        description = issue.get("description")
        if description is None:
            continue
        if not isinstance(description, str):
            raise TrackerIdentityError("GitLab Issue 响应缺少 description")
        if marker not in description.splitlines():
            continue
        if issue.get("project_id") != project_id:
            raise TrackerIdentityError("完整 marker 出现在外部 GitLab 项目")
        if not isinstance(issue.get("iid"), int) or issue["iid"] <= 0:
            raise TrackerIdentityError("匹配的 GitLab Issue 缺少有效 iid")
        matches.append(issue)

    if len(matches) > 1:
        raise TrackerIdentityError("GitLab 中存在多个相同完整 marker，拒绝猜测映射")
    return matches[0] if matches else None


def _json(raw, label):
    try:
        return json.loads(raw)
    except (TypeError, ValueError) as error:
        raise TrackerIdentityError("%s 不是合法 JSON" % label) from error


def _issue(raw, label):
    value = _json(raw, label)
    return parse_issue_page(json.dumps([value]))[0]


def _state(path):
    value = _json(Path(path).read_text(encoding="utf-8"), "state.json")
    if not isinstance(value, dict) or value.get("tracker") != "gitlab":
        raise TrackerIdentityError("当前 state.json 不是 gitlab tracker")
    if not isinstance(value.get("initiative"), dict) or not isinstance(value.get("modules"), dict):
        raise TrackerIdentityError("state.json 缺少 initiative 或 modules 映射")
    return value


def _atomic_state(path, value):
    path = Path(path)
    descriptor, temporary = tempfile.mkstemp(prefix=".%s.spec-guard-" % path.name, dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def _write_projection(path, state, kind, issue, digest, title=None, module_id=None):
    """在远端对象验证后，原子地写入唯一支持的 state 投影字段。"""
    if kind == "initiative":
        entry = dict(state["initiative"])
        entry.update({"issue": issue["iid"], "goalDigest": digest, "title": title})
        state["initiative"] = entry
    else:
        entry = dict(state["modules"].get(module_id) or {})
        entry.update({"issue": issue["iid"], "rowDigest": digest})
        state["modules"][module_id] = entry
    state["updatedAt"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    _atomic_state(path, state)


class GitLabClient(object):
    """只封装本模块需要的受限 glab API 调用。"""

    def __init__(self):
        self.project_id = None

    def call(self, *args):
        try:
            result = subprocess.run(["glab"] + list(args), capture_output=True, text=True)
        except OSError as error:
            raise TrackerIdentityError("glab 不可执行") from error
        if result.returncode != 0:
            raise TrackerIdentityError("GitLab API 调用失败")
        return result.stdout

    def initialize(self):
        self.call("auth", "status")
        repo = _json(self.call("repo", "view", "--output", "json"), "glab repo view")
        path = repo.get("path_with_namespace") if isinstance(repo, dict) else None
        if not isinstance(path, str) or not path:
            raise TrackerIdentityError("glab repo view 缺少项目路径")
        project = _json(self.call("api", "projects/%s" % quote(path, safe="")), "GitLab 项目")
        project_id = project.get("id") if isinstance(project, dict) else None
        if not isinstance(project_id, int) or project_id <= 0:
            raise TrackerIdentityError("GitLab 项目缺少有效 id")
        self.project_id = project_id

    def read_issue(self, iid):
        return _issue(self.call("api", "projects/%s/issues/%s" % (self.project_id, iid)), "GitLab Issue")

    def search(self, marker):
        query = urlencode({"search": marker, "per_page": "100"})
        # glab 的 --paginate 负责拉完 REST 页；失败不把首页误当全量。
        raw = self.call("api", "projects/%s/issues?%s" % (self.project_id, query), "--paginate")
        return parse_issue_page(raw)

    def create_issue(self, title, description):
        raw = self.call("api", "-X", "POST", "projects/%s/issues" % self.project_id,
                        "-f", "title=%s" % title, "-f", "description=%s" % description)
        return _issue(raw, "新建 GitLab Issue")

    def current_username(self):
        user = _json(self.call("api", "user"), "GitLab current user")
        username = user.get("username") if isinstance(user, dict) else None
        if not isinstance(username, str) or not username:
            raise TrackerIdentityError("GitLab current user 缺少 username")
        return username


def _plan_task_iids(plan_path):
    try:
        text = Path(plan_path).read_text(encoding="utf-8")
    except OSError as error:
        raise TrackerIdentityError("plan.md 无法读取") from error
    matches = re.findall(r"^> Tasks tracked in GitLab Issues:\s*((?:#[1-9][0-9]*(?:,\s*#[1-9][0-9]*)*))\s*$",
                         text, re.M)
    if len(matches) != 1:
        raise TrackerIdentityError("plan.md 必须恰好有一个 GitLab task 索引")
    values = [int(value[1:]) for value in re.findall(r"#[1-9][0-9]*", matches[0])]
    if not values or len(values) != len(set(values)):
        raise TrackerIdentityError("GitLab task 索引为空或重复")
    return values


def _git(project, *args):
    result = subprocess.run(["git", "-C", str(project)] + list(args), capture_output=True, text=True)
    if result.returncode:
        raise TrackerIdentityError(result.stderr.strip() or "Git 命令失败")
    return result.stdout.strip()


def _default_base(project):
    probe = subprocess.run(["git", "-C", str(project), "symbolic-ref", "--short",
                            "refs/remotes/origin/HEAD"], capture_output=True, text=True)
    remote = probe.stdout.strip() if probe.returncode == 0 else ""
    name = remote[7:] if remote.startswith("origin/") else ""
    for candidate in (name, "main", "master"):
        if candidate and subprocess.run(["git", "-C", str(project), "show-ref", "--verify", "--quiet",
                                         "refs/heads/" + candidate]).returncode == 0:
            return candidate
    if name and subprocess.run(["git", "-C", str(project), "show-ref", "--verify", "--quiet",
                               "refs/remotes/origin/" + name]).returncode == 0:
        return "origin/" + name
    raise TrackerIdentityError("无法确定默认基线，拒绝选择 GitLab task")


def _closed_by_commit(project):
    base = _default_base(project)
    messages = _git(project, "log", "--format=%B", "%s..HEAD" % base)
    return set(int(value) for value in re.findall(
        r"(?im)^\s*(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#([1-9][0-9]*)\b", messages))


def select_next(project, map_path, state_path, plan_path):
    """读完全部必需事实后选择一个 GitLab task，再原子更新当前 binding。"""
    from workspace_binding import inspect_workspace, set_task_binding

    binding_result = inspect_workspace(project, map_path, state_path)
    if not binding_result.get("ok"):
        return binding_result
    binding = binding_result["binding"]
    if binding.get("tracker") != "gitlab":
        return reject_task("context-mismatch", "当前 binding 不是 gitlab tracker")
    try:
        plan_iids = _plan_task_iids(plan_path)
        client = GitLabClient()
        client.initialize()
        issues = dict((iid, client.read_issue(iid)) for iid in plan_iids)
        selected = select_task_candidate(binding, plan_iids, issues, client.project_id,
                                         client.current_username(), _closed_by_commit(project))
        if not selected.get("ok") or selected["code"] in ("task-in-progress", "no-eligible-task"):
            return selected
        updated = set_task_binding(project, map_path, state_path, selected["taskIssue"],
                                   expected_previous=binding.get("taskIssue"))
        if not updated.get("ok"):
            return updated
        return dict(selected, binding=updated["binding"])
    except (OSError, TrackerIdentityError, ValueError) as error:
        return reject_task("context-unknown", str(error))


def _map_projection(map_path):
    from capability_map import parse_map as parse_capability_map

    map_path = Path(map_path)
    digest_spec = importlib.util.spec_from_file_location("spec_guard_digest", Path(__file__).with_name("spec-digest.py"))
    digest_module = importlib.util.module_from_spec(digest_spec)
    digest_spec.loader.exec_module(digest_module)
    text = map_path.read_text(encoding="utf-8")
    if re.search(r"- \[ \]", text):
        raise TrackerIdentityError("能力图评审记录尚未全部勾选")
    title = re.search(r"^# Capability Map:\s*(.+)$", text, re.M)
    parsed = parse_capability_map(map_path)
    digest = digest_module.compute(map_path)
    if not title or not parsed.goal or not digest.get("goalDigest") or digest.get("placeholder"):
        raise TrackerIdentityError("能力图缺少可投影的标题、目标或 digest")
    rows = dict((item["id"], item["rowDigest"]) for item in digest["rows"])
    modules = dict((row.module_id, row) for row in parsed.rows)
    if set(rows) != set(modules) or not parsed.order:
        raise TrackerIdentityError("能力图模块与 digest 不一致")
    return {"title": title.group(1).strip(), "goal": parsed.goal,
            "goalDigest": digest["goalDigest"], "rows": rows,
            "modules": modules, "order": parsed.order}


def _resolve_projection(client, entry, marker, digest, kind, module_id=None):
    issue_id = entry.get("issue") if isinstance(entry, dict) else None
    stored_digest = entry.get("goalDigest" if kind == "initiative" else "rowDigest") if isinstance(entry, dict) else None
    if issue_id is not None:
        if not isinstance(issue_id, int) or issue_id <= 0 or stored_digest != digest:
            raise TrackerIdentityError("state.json 的 %s 投影不完整或已过期，拒绝覆盖" % kind)
        issue = client.read_issue(issue_id)
        if recover_exact_issue([issue], marker, client.project_id, page_complete=True) is None:
            raise TrackerIdentityError("state.json 记录的 %s Issue 缺少预期 marker" % kind)
        return issue, False

    candidates = client.search(marker)
    found = recover_exact_issue(candidates, marker, client.project_id, page_complete=True)
    if found is not None:
        return found, True
    return None, True


def _create_or_recover(client, title, description, marker):
    try:
        issue = client.create_issue(title, description)
        if recover_exact_issue([issue], marker, client.project_id, page_complete=True) is None:
            raise TrackerIdentityError("新建 GitLab Issue 缺少预期 marker")
        return issue
    except TrackerIdentityError:
        # 网络在服务端写入后断开时，仅允许通过完整 marker 恢复一次副作用。
        found = recover_exact_issue(client.search(marker), marker, client.project_id, page_complete=True)
        if found is None:
            raise
        return found


def sync_map(project, map_path, state_path, confirm):
    projection = _map_projection(map_path)
    state = _state(state_path)
    if "workflowStage" in state:
        raise TrackerIdentityError("workflowStage 存在：tracker 尚未激活，禁止同步")
    client = GitLabClient()
    client.initialize()
    print("将同步 initiative: %s" % projection["title"])
    for module_id in projection["order"]:
        print("  - 模块: %s — %s" % (module_id, projection["modules"][module_id].responsibility))
    if not confirm:
        print("未写入任何远端或本地状态。确认创建请运行：/spec-guard:sync-map --confirm")
        return

    marker = initiative_marker(projection["goalDigest"])
    initiative, changed = _resolve_projection(client, state["initiative"], marker,
                                               projection["goalDigest"], "initiative")
    if initiative is None:
        initiative = _create_or_recover(client, projection["title"],
            "%s\n\n%s" % (projection["goal"], marker), marker)
    if changed:
        _write_projection(state_path, state, "initiative", initiative,
                          projection["goalDigest"], title=projection["title"])
        state = _state(state_path)

    for module_id in projection["order"]:
        row = projection["modules"][module_id]
        digest = projection["rows"][module_id]
        marker = module_marker(module_id, digest)
        issue, changed = _resolve_projection(client, state["modules"].get(module_id), marker,
                                              digest, "module", module_id)
        if issue is None:
            body = "%s\n\nInitiative: #%s\n%s" % (row.responsibility, initiative["iid"], marker)
            issue = _create_or_recover(client, module_id, body, marker)
        if changed:
            _write_projection(state_path, state, "module", issue, digest, module_id=module_id)
            state = _state(state_path)

    if not state.get("activeModule"):
        state["activeModule"] = projection["order"][0]
        state["updatedAt"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        _atomic_state(state_path, state)
    print("✅ GitLab 投影已验证，initiative #%s" % initiative["iid"])


def main(argv=None):
    parser = argparse.ArgumentParser(description="Spec Guard GitLab tracker helper")
    parser.add_argument("action", choices=("sync", "next"))
    parser.add_argument("--project", required=True)
    parser.add_argument("--map", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--plan")
    parser.add_argument("--confirm", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.action == "sync":
            sync_map(args.project, args.map, args.state, args.confirm)
        else:
            if not args.plan:
                raise TrackerIdentityError("next 必须指定 --plan")
            result = select_next(args.project, args.map, args.state, args.plan)
            print(json.dumps(result, ensure_ascii=False, sort_keys=True))
            return 0 if result.get("ok") else 1
    except (OSError, TrackerIdentityError) as error:
        print("❌ %s" % error, file=__import__("sys").stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
