"""GitLab 能力图投影的严格身份基元。

恢复只能基于完整、版本化 marker；标题和部分文本只是搜索候选，不能建立身份。
本模块不执行 glab、文件或 tracker 写入，供同步器和后续任务选择器共享。
"""
from __future__ import print_function

import argparse
import datetime
import importlib.util
import json
from pathlib import Path
import re
import subprocess
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
    temporary = path.with_name(".%s.spec-guard-tmp" % path.name)
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


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
    parser.add_argument("action", choices=("sync",))
    parser.add_argument("--project", required=True)
    parser.add_argument("--map", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--confirm", action="store_true")
    args = parser.parse_args(argv)
    try:
        sync_map(args.project, args.map, args.state, args.confirm)
    except (OSError, TrackerIdentityError) as error:
        print("❌ %s" % error, file=__import__("sys").stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
