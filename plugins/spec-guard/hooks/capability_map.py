"""能力图的唯一表格、依赖与构建顺序解析器。"""
from __future__ import print_function

import re


MODULE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class MapError(ValueError):
    """能力图不能作为可靠输入时的可诊断错误。"""


class ModuleRow(object):
    def __init__(self, module_id, normalized_row, depends_on, responsibility=None):
        self.module_id = module_id
        self.normalized_row = normalized_row
        self.depends_on = depends_on
        self.responsibility = responsibility


class ParsedMap(object):
    def __init__(self, rows, goal, order, order_groups=None):
        self.rows = rows
        self.goal = goal
        self.order = order
        self.order_groups = order_groups


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


def _table_cells(line):
    text = line.strip()[1:]
    if text.endswith("|"):
        text = text[:-1]
    return [cell.strip() for cell in text.split("|")]


def _parse_rows(lines, strict=False):
    rows = []
    for line in lines:
        if not line.lstrip().startswith("|"):
            continue
        # 摘要兼容模式保留旧规范化，严格模式只剥一层表格边框，保留空依赖列。
        cells = (_table_cells(line) if strict else
                 [cell.strip() for cell in line.strip().strip("|").split("|")])
        if len(cells) < 3:
            continue
        first = cells[0]
        if not first or first.lower() == "module id" or set(first) <= set("-: "):
            continue
        module_id = _strip_ticks(first)
        normalized = "|".join([module_id] + cells[1:])
        rows.append(ModuleRow(module_id, normalized, _parse_dependencies(cells[2]), cells[1]))
    return rows


def _visible_lines(lines):
    """严格图输入不使用 fenced code block 中的示例。"""
    visible = []
    fence = None
    for line in lines:
        match = re.match(r"^\s*(`{3,}|~{3,})(.*)$", line)
        if fence:
            if (match and match[1][0] == fence[0] and len(match[1]) >= len(fence)
                    and not match[2].strip()):
                fence = None
            visible.append("")
        elif match:
            fence = match[1]
            visible.append("")
        else:
            visible.append(line)
    return visible


def _strict_rows(lines):
    headers = [index for index, line in enumerate(lines)
               if line.lstrip().startswith("|") and _table_cells(line)[0].lower() == "module id"]
    if len(headers) != 1:
        raise MapError("必须恰好有一个模块表")
    start = headers[0]
    header = _table_cells(lines[start])
    if [cell.lower() for cell in header[:3]] != ["module id", "responsibility", "depends on"]:
        raise MapError("模块表必须包含 Module id、Responsibility、Depends on")
    separator = _table_cells(lines[start + 1]) if start + 1 < len(lines) else []
    if (len(separator) != len(header) or
            any(not re.fullmatch(r":?-{3,}:?", cell) for cell in separator)):
        raise MapError("模块表缺少有效的表头分隔行")
    selected = []
    for line in lines[start + 2:]:
        if not line.lstrip().startswith("|"):
            break
        values = _table_cells(line)
        if len(values) != len(header) or not values[0]:
            raise MapError("模块表存在不完整的行")
        raw = _strip_ticks(values[2])
        if raw not in ("", "-", "—"):
            dependencies = [_strip_ticks(item) for item in raw.split(",")]
            if any(not item for item in dependencies) or len(set(dependencies)) != len(dependencies):
                raise MapError("依赖列表不能包含空项或重复项")
        selected.append(line)
    rows = _parse_rows(selected, strict=True)
    if len(rows) != len(selected):
        raise MapError("模块表存在无效的模块行")
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
    declarations = []
    for line in lines:
        match = re.match(r"^Build order:\s*(.*)$", line.strip(), re.IGNORECASE)
        if not match:
            continue
        raw = match.group(1).strip()
        if not raw:
            raise MapError("Build order 不能为空")
        groups = [[_strip_ticks(item) for item in group.split(",")]
                  for group in re.split(r"\s*(?:→|->)\s*", raw)]
        if any(not item for group in groups for item in group):
            raise MapError("Build order 格式无效")
        declarations.append(groups)
    if len(declarations) != 1:
        raise MapError("必须恰好有一个 Build order")
    return declarations[0]


def _validate(rows, order_groups):
    order = [module_id for group in order_groups for module_id in group]
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
    positions = {module_id: index for index, group in enumerate(order_groups)
                 for module_id in group}
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
    if not validate_graph:
        # 历史图可没有 Build order，但仍只承认唯一模块表；不能把检查点、
        # 风险或示例表的首列误作 module id，进而制造投影指纹假警报。
        lines = _visible_lines(lines)
        headers = [line for line in lines if line.lstrip().startswith("|")
                   and _table_cells(line)[0].lower() == "module id"]
        rows = _strict_rows(lines) if headers else []
        goal = _parse_goal(lines)
        return ParsedMap(rows, goal, [row.module_id for row in rows])
    lines = _visible_lines(lines)
    rows = _strict_rows(lines)
    goal = _parse_goal(lines)
    groups = _parse_declared_order(lines)
    _validate(rows, groups)
    order = [module_id for group in groups for module_id in group]
    return ParsedMap(rows, goal, order, groups)
