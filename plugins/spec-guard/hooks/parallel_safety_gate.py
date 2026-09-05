"""并行安全门的边界声明解析。"""
from __future__ import print_function

import json
import importlib.util
import os
import re
import stat
import unicodedata


FIELDS = ("paths", "publicInterfaces", "migrations", "globalConfig", "testResources")


class BoundaryError(ValueError):
    pass


def _block_after_heading(text):
    headings = list(re.finditer(r"^##\s+Parallel Boundary\s*$", text, re.MULTILINE))
    if len(headings) != 1:
        raise BoundaryError("必须恰好有一个 ## Parallel Boundary")
    tail = text[headings[0].end():]
    match = re.match(r"\s*```json\s*\n(.*?)\n```", tail, re.DOTALL)
    if not match:
        raise BoundaryError("Parallel Boundary 必须紧接 json code block")
    return match.group(1)


def _path(value):
    if (not isinstance(value, str) or not value or value != value.strip() or
            value.startswith("/") or re.match(r"^[A-Za-z]:", value) or
            "\\" in value or ".." in value.split("/") or
            any(char in value for char in "*?[]{}") or
            any(unicodedata.category(char) in ("Cc", "Cf") for char in value)):
        raise BoundaryError("paths 必须是无通配符的仓库相对路径: %s" % value)
    return "/".join(part for part in value.split("/") if part not in ("", ".")) or "."


def parse_boundary(path):
    with open(path, encoding="utf-8") as handle:
        try:
            data = json.loads(_block_after_heading(handle.read()))
        except json.JSONDecodeError as error:
            raise BoundaryError("Parallel Boundary JSON 无效: %s" % error)
    return _validate_boundary(data)


def _validate_boundary(data):
    if not isinstance(data, dict) or set(data) != set(FIELDS):
        raise BoundaryError("Parallel Boundary 必须且只能包含五个必填字段")
    result = {}
    for field in FIELDS:
        values = data[field]
        if not isinstance(values, list) or any(not isinstance(value, str) for value in values):
            raise BoundaryError("%s 必须是字符串数组" % field)
        # paths 保留原声明，先验证再规范化；不能 strip 掩盖歧义。
        values = sorted(set(values if field == "paths" else (value.strip() for value in values)))
        if any(not value for value in values):
            raise BoundaryError("%s 不能有空值" % field)
        result[field] = values
    for value in result["paths"]:
        _path(value)
    return result


def _paths_overlap(left, right):
    left = () if left == "." else tuple(left.split("/"))
    right = () if right == "." else tuple(right.split("/"))
    return left[:len(right)] == right or right[:len(left)] == left


def _alias(value):
    return unicodedata.normalize("NFC", value).casefold()


def _physical_path(project, path):
    """只读元数据；逐级持有目录 fd，声明中的链接不会被跟随。"""
    descriptor = None
    try:
        if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
            return {"status": "needs-review", "reason": "平台不支持不跟随链接的目录检查"}
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        descriptor = os.open(os.path.realpath(project), flags)
        parts = [] if path == "." else path.split("/")
        for index, part in enumerate(parts):
            aliases = [name for name in os.listdir(descriptor) if name != part and _alias(name) == _alias(part)]
            if aliases:
                return {"status": "needs-review", "reason": "目录组件存在大小写或 Unicode 别名: %s" % part}
            try:
                metadata = os.stat(part, dir_fd=descriptor, follow_symlinks=False)
            except FileNotFoundError:
                return {"status": "not-created", "reason": "路径尚未创建，仅完成词法检查"}
            if stat.S_ISLNK(metadata.st_mode):
                return {"status": "needs-review", "reason": "路径包含符号链接，未跟随目标: %s" % part}
            if not stat.S_ISREG(metadata.st_mode) and not stat.S_ISDIR(metadata.st_mode):
                return {"status": "needs-review", "reason": "路径组件不是普通文件或目录: %s" % part}
            if index < len(parts) - 1:
                child = os.open(part, flags, dir_fd=descriptor)
                os.close(descriptor)
                descriptor = child
        return {"status": "checked", "reason": "当前已有组件未发现链接或别名；不保证后续写入时状态不变"}
    except (OSError, TypeError, ValueError, NotImplementedError) as error:
        return {"status": "needs-review", "reason": "无法验证物理路径: %s" % error}
    finally:
        if descriptor is not None:
            os.close(descriptor)


def classify_group(boundaries, project=None):
    """以最保守的规则分类一个 readiness 候选组。"""
    if (not isinstance(boundaries, dict) or len(boundaries) < 2 or
            any(not isinstance(module, str) or not module for module in boundaries)):
        return {"classification": "needs-review", "evidence": [
            {"category": "invalid-group", "reason": "需要至少两个有名称的模块边界"}
        ], "pathDeclarations": {}}

    valid, declarations, uncertain, evidence = {}, {}, [], []
    for module in sorted(boundaries):
        try:
            valid[module] = _validate_boundary(boundaries[module])
        except BoundaryError as error:
            uncertain.append({"category": "invalid-boundary", "modules": [module], "reason": str(error)})
            continue
        declarations[module] = [{"raw": value, "normalized": _path(value)} for value in valid[module]["paths"]]
        if not declarations[module]:
            uncertain.append({"category": "empty-paths", "modules": [module], "reason": "没有声明实际写入路径"})
        if project is not None:
            for item in declarations[module]:
                item["physical"] = _physical_path(project, item["normalized"])
                if item["physical"]["status"] == "needs-review":
                    uncertain.append({"category": "physical-path", "modules": [module],
                                      "path": item["raw"], "reason": item["physical"]["reason"]})

    if project is None:
        uncertain.append({"category": "physical-context", "modules": sorted(valid),
                          "reason": "缺少项目上下文，未进行物理路径检查"})

    modules = sorted(valid)
    for module in modules:
        boundary = valid[module]
        for category in ("migrations", "globalConfig", "testResources"):
            if boundary[category]:
                evidence.append({"category": category, "modules": [module],
                                 "values": sorted(boundary[category])})

    for index, left_module in enumerate(modules):
        left = valid[left_module]
        for right_module in modules[index + 1:]:
            right = valid[right_module]
            paths = sorted({"%s|%s" % (a, b)
                            for a in (item["normalized"] for item in declarations[left_module])
                            for b in (item["normalized"] for item in declarations[right_module])
                            if _paths_overlap(a, b)})
            if paths:
                evidence.append({"category": "paths", "modules": [left_module, right_module],
                                 "values": paths})
            aliases = sorted({"%s|%s" % (a["raw"], b["raw"])
                              for a in declarations[left_module] for b in declarations[right_module]
                              if not _paths_overlap(a["normalized"], b["normalized"]) and
                              _paths_overlap(_alias(a["normalized"]), _alias(b["normalized"]))})
            if aliases:
                uncertain.append({"category": "path-alias", "modules": [left_module, right_module],
                                  "values": aliases, "reason": "大小写或 Unicode 规范化后可能重叠，不能证明路径互异"})
            interfaces = sorted(set(left["publicInterfaces"]) & set(right["publicInterfaces"]))
            if interfaces:
                evidence.append({"category": "publicInterfaces",
                                 "modules": [left_module, right_module], "values": interfaces})

    classification = "sequential-required" if evidence else "needs-review" if uncertain else "manual-parallel-eligible"
    return {"classification": classification, "evidence": evidence + uncertain, "pathDeclarations": declarations,
            "scopeNotice": "仅检查声明与当前路径元数据，不证明物理隔离、未来写入范围或运行时资源安全。"}


def readiness_report(project, refresh=False):
    path = os.path.join(os.path.dirname(__file__), "parallel-readiness.py")
    spec = importlib.util.spec_from_file_location("parallel_readiness_runtime", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.report(project, refresh=refresh)


def gate_report(project, refresh=False):
    readiness = readiness_report(project, refresh=refresh)
    results = []
    for group in readiness["candidateGroups"]:
        boundaries = {}
        for module_id in group["modules"]:
            try:
                boundaries[module_id] = parse_boundary(
                    os.path.join(project, "spec", module_id + ".md")
                )
            except (BoundaryError, OSError):
                boundaries[module_id] = None
        results.append(dict(group, **classify_group(boundaries, project=project)))
    return {"ok": True, "base": readiness["base"], "groups": results,
            "warnings": readiness["warnings"]}
