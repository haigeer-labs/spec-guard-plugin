"""Strict, read-only parser for an opt-in project documentation baseline."""
import argparse
import json
from pathlib import Path


UNIVERSAL_CONCERNS = frozenset((
    "product-direction", "architecture", "developer-entry",
))
STATUSES = frozenset((
    "target", "in-progress", "verified", "pending", "not-applicable",
))


class BaselineError(ValueError):
    """The baseline cannot safely be treated as documentation guidance."""


class Entry(object):
    def __init__(self, concern, authority, status, rationale):
        self.concern = concern
        self.authority = authority
        self.status = status
        self.rationale = rationale


class Baseline(object):
    def __init__(self, state, entries):
        self.state = state
        self.entries = entries


def _cells(line):
    text = line.strip()
    if not text.startswith("|"):
        return None
    text = text[1:]
    if text.endswith("|"):
        text = text[:-1]
    return [cell.strip() for cell in text.split("|")]


def _visible_lines(lines):
    visible = []
    fence = None
    for line in lines:
        marker = line.lstrip()
        if fence:
            if marker.startswith(fence):
                fence = None
            visible.append("")
        elif marker.startswith(("```", "~~~")):
            fence = marker[:3]
            visible.append("")
        else:
            visible.append(line)
    return visible


def _authority(value):
    value = value.strip().strip("`").strip()
    return None if value in ("", "-", "—") else value


def _table(lines):
    headers = []
    for index, line in enumerate(lines):
        cells = _cells(line)
        if cells and [cell.lower() for cell in cells] == [
                "concern", "authority", "status", "rationale"]:
            headers.append(index)
    if len(headers) != 1:
        raise BaselineError("must contain exactly one baseline table")
    start = headers[0]
    if start + 1 >= len(lines):
        raise BaselineError("baseline table is missing its separator")
    separator = _cells(lines[start + 1])
    if separator is None or len(separator) != 4 or any(
            not cell or set(cell) - set("-:") for cell in separator):
        raise BaselineError("baseline table has an invalid separator")
    rows = []
    for line in lines[start + 2:]:
        cells = _cells(line)
        if cells is None:
            break
        if len(cells) != 4:
            raise BaselineError("baseline table has an incomplete row")
        rows.append(cells)
    if not rows:
        raise BaselineError("baseline table has no entries")
    return rows


def parse_baseline(path):
    """Parse one explicit baseline; a missing file means the feature is not enabled."""
    path = Path(path)
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise BaselineError("baseline must be a regular file")
    if not path.exists():
        return Baseline("absent", {})
    rows = _table(_visible_lines(path.read_text(encoding="utf-8").splitlines()))
    entries = {}
    for concern, authority_text, status, rationale in rows:
        concern = concern.strip()
        if not concern:
            raise BaselineError("baseline concern cannot be empty")
        if concern in entries:
            raise BaselineError("duplicate concern: %s" % concern)
        if status not in STATUSES:
            raise BaselineError("unknown status: %s" % status)
        authority = _authority(authority_text)
        rationale = rationale.strip()
        if not rationale:
            raise BaselineError("rationale is required for %s" % concern)
        if status == "not-applicable":
            if authority is not None:
                raise BaselineError("not-applicable concern cannot name an authority")
        elif authority is None:
            raise BaselineError("authority is required for %s" % concern)
        entries[concern] = Entry(concern, authority, status, rationale)
    missing = sorted(UNIVERSAL_CONCERNS - set(entries))
    if missing:
        raise BaselineError("missing universal concern: %s" % ", ".join(missing))
    return Baseline("valid", entries)


def _as_json(baseline):
    return {
        "state": baseline.state,
        "entries": dict((concern, {
            "authority": entry.authority,
            "status": entry.status,
            "rationale": entry.rationale,
        }) for concern, entry in sorted(baseline.entries.items())),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    parser.add_argument("--format", choices=("json",), default="json")
    args = parser.parse_args(argv)
    project = Path(args.project)
    if not project.is_dir():
        print(json.dumps({"state": "invalid", "error": "project is not a directory"},
                         ensure_ascii=False))
        return 1
    try:
        baseline = parse_baseline(project / "docs" / "DOCUMENTATION-BASELINE.md")
    except (OSError, UnicodeError, BaselineError) as error:
        print(json.dumps({"state": "invalid", "error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(_as_json(baseline), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
