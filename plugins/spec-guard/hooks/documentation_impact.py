"""Read explicit module documentation-impact decisions without inspecting code."""
import argparse
import json
import re
from pathlib import Path

from documentation_baseline import BaselineError, _visible_lines, parse_baseline


DECISIONS = frozenset(("follow", "update", "create", "pending", "not-applicable"))
MODULE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class ImpactError(ValueError):
    """The module impact cannot safely be treated as an explicit decision."""


class Decision(object):
    def __init__(self, concern, decision, rationale):
        self.concern = concern
        self.decision = decision
        self.rationale = rationale


class Delivery(object):
    def __init__(self, concern, artifact, rationale):
        self.concern = concern
        self.artifact = artifact
        self.rationale = rationale


class Impact(object):
    def __init__(self, state, decisions, delivery):
        self.state = state
        self.decisions = decisions
        self.delivery = delivery


def _cells(line):
    line = line.strip()
    if not line.startswith("|"):
        return None
    line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [cell.strip() for cell in line.split("|")]


def _table(path, headers, label):
    try:
        lines = _visible_lines(path.read_text(encoding="utf-8").splitlines())
    except (OSError, UnicodeError) as error:
        raise ImpactError("cannot read %s: %s" % (label, error))
    hits = []
    expected = [header.lower() for header in headers]
    for index, line in enumerate(lines):
        cells = _cells(line)
        if cells and [cell.lower() for cell in cells] == expected:
            hits.append(index)
    if len(hits) != 1:
        raise ImpactError("%s must contain exactly one %s table" % (path, label))
    start = hits[0]
    if start + 1 >= len(lines):
        raise ImpactError("%s table is missing its separator" % label)
    separator = _cells(lines[start + 1])
    if separator is None or len(separator) != len(headers) or any(
            not cell or set(cell) - set("-:") for cell in separator):
        raise ImpactError("%s table has an invalid separator" % label)
    rows = []
    for line in lines[start + 2:]:
        cells = _cells(line)
        if cells is None:
            break
        if len(cells) != len(headers):
            raise ImpactError("%s table has an incomplete row" % label)
        rows.append(cells)
    if not rows:
        raise ImpactError("%s table has no entries" % label)
    return rows


def _regular(path, label):
    if path.is_symlink() or not path.is_file():
        raise ImpactError("%s must be a regular file" % label)
    return path


def _decisions(path, baseline):
    entries = {}
    for concern, decision, rationale in _table(
            _regular(path, "module spec"),
            ("Concern", "Decision", "Rationale"), "Documentation impact"):
        if concern in entries:
            raise ImpactError("duplicate concern: %s" % concern)
        if concern not in baseline.entries:
            raise ImpactError("unknown baseline concern: %s" % concern)
        if baseline.entries[concern].status == "not-applicable":
            raise ImpactError("project-level not-applicable concern cannot be decided: %s" % concern)
        if decision not in DECISIONS:
            raise ImpactError("unknown decision: %s" % decision)
        if not rationale:
            raise ImpactError("rationale is required for %s" % concern)
        entries[concern] = Decision(concern, decision, rationale)
    required = set(concern for concern, entry in baseline.entries.items()
                   if entry.status != "not-applicable")
    missing = sorted(required - set(entries))
    if missing:
        raise ImpactError("missing documentation decision: %s" % ", ".join(missing))
    return entries


def _delivery(path, decisions, baseline):
    required = set(concern for concern, decision in decisions.items()
                   if decision.decision in ("update", "create"))
    if not required:
        return {}
    entries = {}
    for concern, artifact, rationale in _table(
            _regular(path, "module plan"),
            ("Concern", "Planned artifact", "Rationale"), "Documentation delivery"):
        if concern in entries:
            raise ImpactError("duplicate delivery concern: %s" % concern)
        if concern not in required:
            raise ImpactError("delivery is only allowed for update/create: %s" % concern)
        artifact = artifact.strip().strip("`").strip()
        if not artifact:
            raise ImpactError("planned artifact is required for %s" % concern)
        if (decisions[concern].decision == "update" and
                artifact != baseline.entries[concern].authority):
            raise ImpactError("planned update must name the baseline authority for %s" %
                              concern)
        if not rationale:
            raise ImpactError("delivery rationale is required for %s" % concern)
        entries[concern] = Delivery(concern, artifact, rationale)
    missing = sorted(required - set(entries))
    if missing:
        raise ImpactError("missing planned delivery: %s" % ", ".join(missing))
    return entries


def parse_impact(project, module):
    """Return explicit impact facts for one module; no baseline means no governance."""
    project = Path(project)
    if not project.is_dir():
        raise ImpactError("project is not a directory")
    if not MODULE_ID.fullmatch(module):
        raise ImpactError("module id must be kebab-case")
    try:
        baseline = parse_baseline(project / "docs" / "DOCUMENTATION-BASELINE.md")
    except BaselineError as error:
        raise ImpactError("invalid documentation baseline: %s" % error)
    if baseline.state == "absent":
        return Impact("absent", {}, {})
    decisions = _decisions(project / "spec" / (module + ".md"), baseline)
    delivery = _delivery(project / "tasks" / module / "plan.md", decisions, baseline)
    return Impact("valid", decisions, delivery)


def _as_json(impact):
    return {
        "state": impact.state,
        "decisions": dict((concern, {
            "decision": item.decision,
            "rationale": item.rationale,
        }) for concern, item in sorted(impact.decisions.items())),
        "delivery": dict((concern, {
            "artifact": item.artifact,
            "rationale": item.rationale,
        }) for concern, item in sorted(impact.delivery.items())),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    parser.add_argument("--module", required=True)
    parser.add_argument("--format", choices=("json",), default="json")
    args = parser.parse_args(argv)
    try:
        impact = parse_impact(args.project, args.module)
    except (ImpactError, OSError, UnicodeError) as error:
        print(json.dumps({"state": "invalid", "error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(_as_json(impact), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
