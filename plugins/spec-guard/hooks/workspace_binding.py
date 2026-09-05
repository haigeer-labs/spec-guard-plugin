#!/usr/bin/env python3
"""为当前 Git worktree 创建并核验 Spec Guard 的本地 tracker binding。

绑定只是用户显式选择的本地上下文，不是任务事实源、锁或并行执行器。任何
无法证明的 Git、能力图、state 或依赖事实都返回结构化的 fail-closed 结果。
"""
from __future__ import print_function

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from capability_map import MapError, parse_map


BINDING_VERSION = 1


class BindingError(ValueError):
    """本地绑定不能被安全地创建或解释。"""


def reject(code, message):
    return {"ok": False, "code": code, "message": message}


def _git(project, *args):
    result = subprocess.run(["git", "-C", str(project)] + list(args), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise BindingError(detail or "无法读取 Git 元数据")
    return result.stdout.strip()


def _git_dir(project):
    project = Path(project).resolve()
    raw = _git(project, "rev-parse", "--git-dir")
    if not raw:
        raise BindingError("当前目录没有 worktree-local Git directory")
    path = Path(raw)
    if not path.is_absolute():
        path = project / path
    path = path.resolve()
    if not path.is_dir():
        raise BindingError("当前 worktree 的 Git directory 不可读取")
    return path


def _git_common_dir(project):
    project = Path(project).resolve()
    raw = _git(project, "rev-parse", "--git-common-dir")
    if not raw:
        raise BindingError("当前目录没有 Git common directory")
    path = Path(raw)
    if not path.is_absolute():
        path = project / path
    path = path.resolve()
    if not path.is_dir():
        raise BindingError("当前 worktree 的 Git common directory 不可读取")
    return path


def _canonical_repo(remote):
    if not isinstance(remote, str):
        raise BindingError("origin remote 无效")
    value = remote.strip()
    if value.startswith("git@") and ":" in value:
        host, path = value[4:].split(":", 1)
        value = "%s/%s" % (host, path)
    else:
        value = re.sub(r"^[a-z][a-z0-9+.-]*://", "", value, flags=re.I)
        value = value.split("@", 1)[-1]
    value = value.rstrip("/")
    if value.endswith(".git"):
        value = value[:-4]
    if not value or "/" not in value or ".." in value.split("/"):
        raise BindingError("origin remote 不是可规范化的仓库地址")
    return value.lower()


def _repo(project):
    return _canonical_repo(_git(project, "remote", "get-url", "origin"))


def _json_file(path, label):
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise BindingError("%s 无法读取: %s" % (label, error))
    if not isinstance(value, dict):
        raise BindingError("%s 必须是对象" % label)
    return value


def _issue(value, label, allow_null=False):
    if allow_null and value is None:
        return None
    if type(value) is not int or value < 1:
        raise BindingError("%s 必须是正 Issue 编号" % label)
    return value


def _facts(project, map_path, state_path):
    parsed = parse_map(map_path)
    state = _json_file(state_path, "state.json")
    tracker = state.get("tracker")
    if tracker not in ("github", "gitlab"):
        raise BindingError("state.json tracker 必须是 github 或 gitlab")
    initiative = state.get("initiative")
    modules = state.get("modules")
    if not isinstance(initiative, dict) or not isinstance(modules, dict):
        raise BindingError("state.json 缺少 initiative 或 modules 映射")
    initiative_issue = _issue(initiative.get("issue"), "initiative.issue")
    rows = dict((row.module_id, row) for row in parsed.rows)
    for module_id in parsed.order:
        module = modules.get(module_id)
        if not isinstance(module, dict):
            raise BindingError("state.json 缺少模块映射: %s" % module_id)
        _issue(module.get("issue"), "modules.%s.issue" % module_id)
    active = state.get("activeModule")
    if not isinstance(active, str) or active not in rows:
        raise BindingError("state.json activeModule 不属于能力图")
    return {
        "gitDir": str(_git_dir(project)),
        "gitCommonDir": str(_git_common_dir(project)),
        "repo": _repo(project),
        "tracker": tracker,
        "initiativeIssue": initiative_issue,
        "modules": modules,
        "rows": rows,
        "activeModule": active,
    }


def _binding_path(facts):
    return Path(facts["gitDir"]) / "spec-guard" / "workspace-binding.json"


def _load_binding(facts):
    path = _binding_path(facts)
    if not path.is_file():
        raise BindingError("当前 worktree 尚未绑定；请显式运行 bind-workspace")
    return _json_file(path, "workspace binding")


def _validate_binding(record, facts):
    if not isinstance(record, dict):
        raise BindingError("workspace binding 必须是对象")
    required = ("version", "gitDir", "repo", "tracker", "initiativeIssue", "moduleId", "moduleIssue", "taskIssue")
    if set(record) != set(required):
        raise BindingError("workspace binding 字段不完整或包含未知字段")
    if record["version"] != BINDING_VERSION:
        raise BindingError("workspace binding version 不支持")
    for field in ("gitDir", "repo", "tracker", "moduleId"):
        if not isinstance(record[field], str) or not record[field]:
            raise BindingError("workspace binding 字段无效: %s" % field)
    _issue(record["initiativeIssue"], "binding.initiativeIssue")
    _issue(record["moduleIssue"], "binding.moduleIssue")
    _issue(record["taskIssue"], "binding.taskIssue", allow_null=True)
    if record["gitDir"] != facts["gitDir"]:
        return reject("context-mismatch", "binding 属于另一个 worktree")
    if record["repo"] != facts["repo"]:
        return reject("context-mismatch", "binding origin 与当前仓库不匹配")
    if record["tracker"] != facts["tracker"]:
        return reject("context-mismatch", "binding tracker 与 state.json 不匹配")
    if record["initiativeIssue"] != facts["initiativeIssue"]:
        return reject("context-mismatch", "binding initiative 与 state.json 不匹配")
    row = facts["rows"].get(record["moduleId"])
    module = facts["modules"].get(record["moduleId"])
    if row is None or not isinstance(module, dict) or record["moduleIssue"] != module.get("issue"):
        return reject("context-mismatch", "binding module 与能力图/state.json 映射不匹配")
    return {"ok": True, "code": "ok", "binding": record}


def _has_closing_commit(project, issue):
    messages = _git(project, "log", "--format=%B", "HEAD")
    pattern = r"(?im)^\s*(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*#%d\b" % issue
    return re.search(pattern, messages) is not None


def _validate_dependencies(project, facts, module_id):
    if module_id == facts["activeModule"]:
        return None
    if facts["gitDir"] == facts["gitCommonDir"]:
        return reject("context-mismatch", "非默认模块只能绑定到 linked worktree")
    row = facts["rows"][module_id]
    unresolved = []
    for predecessor in row.depends_on:
        issue = facts["modules"][predecessor]["issue"]
        if not _has_closing_commit(project, issue):
            unresolved.append("%s (#%d)" % (predecessor, issue))
    if unresolved:
        return reject("dependency-blocked", "当前 HEAD 未证明前置模块已完成: %s" % ", ".join(unresolved))
    return None


def inspect_workspace(project, map_path, state_path):
    """验证当前 worktree 已有 binding；不修复、不创建任何记录。"""
    try:
        facts = _facts(project, map_path, state_path)
        record = _load_binding(facts)
        result = _validate_binding(record, facts)
        if not result["ok"]:
            return result
        blocked = _validate_dependencies(project, facts, record["moduleId"])
        return blocked or result
    except (BindingError, MapError, OSError, ValueError) as error:
        return reject("context-unknown", str(error))


def _atomic_write(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".workspace-binding-", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except OSError as error:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise BindingError("无法写入 workspace binding: %s" % error)


def bind_workspace(project, map_path, state_path, module_id, task_issue=None, replace=False):
    """显式创建当前 worktree binding；已有不同 binding 必须要求 replace。"""
    try:
        facts = _facts(project, map_path, state_path)
        if not isinstance(module_id, str) or module_id not in facts["rows"]:
            raise BindingError("请求的 module 不属于能力图")
        _issue(task_issue, "taskIssue", allow_null=True)
        blocked = _validate_dependencies(project, facts, module_id)
        if blocked:
            return blocked
        record = {
            "version": BINDING_VERSION,
            "gitDir": facts["gitDir"],
            "repo": facts["repo"],
            "tracker": facts["tracker"],
            "initiativeIssue": facts["initiativeIssue"],
            "moduleId": module_id,
            "moduleIssue": facts["modules"][module_id]["issue"],
            "taskIssue": task_issue,
        }
        path = _binding_path(facts)
        if path.exists() or path.is_symlink():
            current = inspect_workspace(project, map_path, state_path)
            if current.get("ok") and current.get("binding") == record:
                return dict(current, created=False)
            if not replace:
                return reject("context-mismatch", "已有不同或无效 binding；确认目标后使用 --replace 显式替换")
        _atomic_write(path, record)
        return {"ok": True, "code": "ok", "binding": record, "created": True}
    except (BindingError, MapError, OSError, ValueError) as error:
        return reject("context-unknown", str(error))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("inspect", "bind"):
        command = commands.add_parser(name)
        command.add_argument("--project", default=".")
        command.add_argument("--map", default="spec/CAPABILITY-MAP.md")
        command.add_argument("--state", default=".agent/state.json")
        command.add_argument("--format", choices=("json",), default="json")
        if name == "bind":
            command.add_argument("--module", required=True)
            command.add_argument("--task-issue", type=int)
            command.add_argument("--replace", action="store_true")
    args = parser.parse_args(argv)
    project = Path(args.project).resolve()
    map_path = Path(args.map)
    state_path = Path(args.state)
    if not map_path.is_absolute():
        map_path = project / map_path
    if not state_path.is_absolute():
        state_path = project / state_path
    if args.command == "inspect":
        result = inspect_workspace(str(project), str(map_path), str(state_path))
    else:
        result = bind_workspace(str(project), str(map_path), str(state_path), args.module,
                                task_issue=args.task_issue, replace=args.replace)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
