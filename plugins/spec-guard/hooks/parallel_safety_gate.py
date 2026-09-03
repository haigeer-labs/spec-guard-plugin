"""并行安全门的边界声明解析。"""
from __future__ import print_function

import json
import re


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
    if (not value or value.startswith("/") or ".." in value.split("/") or
            "*" in value or "?" in value):
        raise BoundaryError("paths 必须是无通配符的仓库相对路径: %s" % value)


def parse_boundary(path):
    with open(path, encoding="utf-8") as handle:
        try:
            data = json.loads(_block_after_heading(handle.read()))
        except json.JSONDecodeError as error:
            raise BoundaryError("Parallel Boundary JSON 无效: %s" % error)
    if not isinstance(data, dict) or set(data) != set(FIELDS):
        raise BoundaryError("Parallel Boundary 必须且只能包含五个必填字段")
    result = {}
    for field in FIELDS:
        values = data[field]
        if not isinstance(values, list) or any(not isinstance(value, str) for value in values):
            raise BoundaryError("%s 必须是字符串数组" % field)
        values = sorted(set(value.strip() for value in values))
        if any(not value for value in values):
            raise BoundaryError("%s 不能有空值" % field)
        result[field] = values
    for value in result["paths"]:
        _path(value)
    return result


def _paths_overlap(left, right):
    return left == right or left.startswith(right + "/") or right.startswith(left + "/")


def classify_group(boundaries):
    """以最保守的规则分类一个 readiness 候选组。"""
    modules = sorted(boundaries)
    missing = [module for module in modules if not isinstance(boundaries[module], dict) or
               set(boundaries[module]) != set(FIELDS)]
    if missing:
        return {"classification": "needs-review", "evidence": [
            {"category": "missing-boundary", "modules": missing}
        ]}

    evidence = []
    for module in modules:
        boundary = boundaries[module]
        for category in ("migrations", "globalConfig", "testResources"):
            if boundary[category]:
                evidence.append({"category": category, "modules": [module],
                                 "values": sorted(boundary[category])})

    for index, left_module in enumerate(modules):
        left = boundaries[left_module]
        for right_module in modules[index + 1:]:
            right = boundaries[right_module]
            paths = sorted({"%s|%s" % (a, b) for a in left["paths"] for b in right["paths"]
                            if _paths_overlap(a, b)})
            if paths:
                evidence.append({"category": "paths", "modules": [left_module, right_module],
                                 "values": paths})
            interfaces = sorted(set(left["publicInterfaces"]) & set(right["publicInterfaces"]))
            if interfaces:
                evidence.append({"category": "publicInterfaces",
                                 "modules": [left_module, right_module], "values": interfaces})

    return {"classification": "sequential-required", "evidence": evidence} if evidence else {
        "classification": "manual-parallel-eligible", "evidence": []
    }
