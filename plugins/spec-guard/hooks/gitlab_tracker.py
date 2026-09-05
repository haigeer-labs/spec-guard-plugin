"""GitLab 能力图投影的严格身份基元。

恢复只能基于完整、版本化 marker；标题和部分文本只是搜索候选，不能建立身份。
本模块不执行 glab、文件或 tracker 写入，供同步器和后续任务选择器共享。
"""
from __future__ import print_function

import json
import re


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
                not isinstance(issue.get("description"), str)):
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
