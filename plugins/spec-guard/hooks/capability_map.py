"""能力图的唯一表格、依赖与构建顺序解析器。"""
from __future__ import print_function

import re


MODULE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class MapError(ValueError):
    """能力图不能作为可靠输入时的可诊断错误。"""


class ModuleRow(object):
    def __init__(self, module_id, normalized_row, depends_on):
        self.module_id = module_id
        self.normalized_row = normalized_row
        self.depends_on = depends_on


class ParsedMap(object):
    def __init__(self, rows, goal, order):
        self.rows = rows
        self.goal = goal
        self.order = order


def _norm_lines(lines):
    out = [line.rstrip() for line in lines]
    while out and not out[0]:
        out.pop(0)
    while out and not out[-1]:
        out.pop()
    return "\n".join(out)


def _strip_ticks(value):
    return value.strip().strip("`").strip()


def _parse_dependencies(value):
    value = _strip_ticks(value)
    if value in ("", "-", "—"):
        return []
    return [_strip_ticks(item) for item in value.split(",") if _strip_ticks(item)]


def _parse_rows(lines):
    rows = []
    for line in lines:
        if not line.lstrip().startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        first = cells[0]
        if not first or first.lower() == "module id" or set(first) <= set("-: "):
            continue
        module_id = _strip_ticks(first)
        normalized = "|".join([module_id] + cells[1:])
        rows.append(ModuleRow(module_id, normalized, _parse_dependencies(cells[2])))
    return rows


def _parse_goal(lines):
    collecting = False
    content = []
    for line in lines:
        if re.match(r"^##\s", line):
            if collecting:
                break
            if re.match(r"^##\s*(目标|Goal)\s*$", line.strip()):
                collecting = True
            continue
        if collecting:
            content.append(line)
    return _norm_lines(content) if collecting else None


def _parse_declared_order(lines):
    for line in lines:
        match = re.match(r"^Build order:\s*(.*)$", line.strip(), re.IGNORECASE)
        if not match:
            continue
        raw = match.group(1).strip()
        if not raw:
            raise MapError("Build order 不能为空")
        order = [_strip_ticks(item) for item in re.split(r"\s*(?:→|->)\s*", raw)]
        if not order or any(not item for item in order):
            raise MapError("Build order 格式无效")
        return order
    raise MapError("缺少 Build order")


def _validate(rows, order):
    ids = [row.module_id for row in rows]
    if not ids:
        raise MapError("能力图没有模块")
    seen = set()
    for module_id in ids:
        if not MODULE_ID.match(module_id):
            raise MapError("module id 不符合 kebab-case: %s" % module_id)
        if module_id in seen:
            raise MapError("重复的 module id: %s" % module_id)
        seen.add(module_id)

    for row in rows:
        for dependency in row.depends_on:
            if dependency == row.module_id:
                raise MapError("模块不能依赖自身: %s" % row.module_id)
            if dependency not in seen:
                raise MapError("未知依赖: %s -> %s" % (row.module_id, dependency))

    if len(order) != len(ids) or set(order) != set(ids):
        raise MapError("Build order 必须恰好包含每个模块一次")
    if len(set(order)) != len(order):
        raise MapError("Build order 包含重复模块")
    positions = dict((module_id, index) for index, module_id in enumerate(order))
    for row in rows:
        for dependency in row.depends_on:
            if positions[dependency] >= positions[row.module_id]:
                raise MapError("Build order 未满足依赖: %s 必须在 %s 之前" %
                               (dependency, row.module_id))

    visiting = set()
    visited = set()
    dependencies = dict((row.module_id, row.depends_on) for row in rows)

    def visit(module_id):
        if module_id in visiting:
            raise MapError("能力图存在循环依赖: %s" % module_id)
        if module_id in visited:
            return
        visiting.add(module_id)
        for dependency in dependencies[module_id]:
            visit(dependency)
        visiting.remove(module_id)
        visited.add(module_id)

    for module_id in ids:
        visit(module_id)


def parse_map(path, validate_graph=True):
    """读取能力图；严格模式额外验证依赖图和 Build order。"""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    rows = _parse_rows(lines)
    goal = _parse_goal(lines)
    if not validate_graph:
        return ParsedMap(rows, goal, [row.module_id for row in rows])
    order = _parse_declared_order(lines)
    _validate(rows, order)
    return ParsedMap(rows, goal, order)
