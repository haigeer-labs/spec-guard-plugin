"""Strict, read-only Proposal contract validation."""
import importlib.util
import re
from pathlib import Path

from capability_map import MODULE_ID, MapError, _visible_lines, parse_map as parse_capability_map


_digest_spec = importlib.util.spec_from_file_location(
    "spec_guard_digest", Path(__file__).with_name("spec-digest.py"))
_digest_module = importlib.util.module_from_spec(_digest_spec)
_digest_spec.loader.exec_module(_digest_module)
compute = _digest_module.compute


PROPOSAL_ID = re.compile(r"^[a-z][a-z0-9-]{2,62}$")
COMMIT = re.compile(r"^[0-9a-f]{40,64}$")
DIGEST = re.compile(r"^[0-9a-f]{12}$")
MARKER = re.compile(r"^<!-- spec-guard-proposal:v1 id=([a-z][a-z0-9-]{2,62}) -->$")
HEADING = re.compile(r"^##\s+(.+?)\s*$")
BUILD_ORDER = re.compile(r"^Build order:\s*(.+?)\s*$", re.IGNORECASE)
ALLOWED_STAGES = frozenset((
    "proposal-stage:draft",
    "proposal-stage:published",
    "proposal-stage:in-review",
    "proposal-stage:accepted",
    "proposal-stage:rejected",
    "proposal-stage:promoted",
))


class ContractError(ValueError):
    """A Proposal cannot be treated as an unambiguous contract."""


class Baseline(object):
    def __init__(self, remote, default_branch, commit, goal_digest, module_digests,
                 build_order):
        self.remote = remote
        self.default_branch = default_branch
        self.commit = commit
        self.goal_digest = goal_digest
        self.module_digests = module_digests
        self.build_order = build_order


class Change(object):
    def __init__(self, module_id, responsibility, depends_on, anchor):
        self.module_id = module_id
        self.responsibility = responsibility
        self.depends_on = depends_on
        self.anchor = anchor


class Proposal(object):
    def __init__(self, proposal_id, marker, baseline, change):
        self.proposal_id = proposal_id
        self.marker = marker
        self.baseline = baseline
        self.change = change


def _cells(line):
    line = line.strip()
    if not line.startswith("|"):
        return None
    line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [cell.strip() for cell in line.split("|")]


def _read_visible(path, label):
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise ContractError("%s must be a regular file" % label)
    try:
        return _visible_lines(path.read_text(encoding="utf-8").splitlines())
    except (OSError, UnicodeError) as error:
        raise ContractError("cannot read %s: %s" % (label, error))


def _sections(lines):
    sections = []
    current = None
    for line in lines:
        match = HEADING.match(line.strip())
        if match:
            if current is not None:
                sections.append(current)
            current = (match.group(1), [])
        elif current is not None:
            current[1].append(line)
    if current is not None:
        sections.append(current)
    expected = ["Summary", "Capability map baseline", "Change", "Tracker contract"]
    names = [name for name, _ in sections]
    if names != expected:
        raise ContractError("Proposal must contain exactly these top-level sections in order: %s" %
                            ", ".join(expected))
    return dict(sections)


def _table(lines, headers, label):
    expected = [header.lower() for header in headers]
    hits = []
    for index, line in enumerate(lines):
        cells = _cells(line)
        if cells and [cell.lower() for cell in cells] == expected:
            hits.append(index)
    if len(hits) != 1:
        raise ContractError("%s must contain exactly one table" % label)
    start = hits[0]
    if start + 1 >= len(lines):
        raise ContractError("%s table is missing its separator" % label)
    separator = _cells(lines[start + 1])
    if separator is None or len(separator) != len(headers) or any(
            not cell or set(cell) - set("-:") for cell in separator):
        raise ContractError("%s table has an invalid separator" % label)
    rows = []
    for line in lines[start + 2:]:
        cells = _cells(line)
        if cells is None:
            break
        if len(cells) != len(headers):
            raise ContractError("%s table has an incomplete row" % label)
        rows.append(cells)
    if not rows:
        raise ContractError("%s table has no entries" % label)
    return rows


def _field_table(lines, required, label):
    values = {}
    for field, value in _table(lines, ("Field", "Value"), label):
        if field in values:
            raise ContractError("duplicate %s field: %s" % (label, field))
        values[field] = value.strip()
    if set(values) != set(required):
        missing = sorted(set(required) - set(values))
        extra = sorted(set(values) - set(required))
        parts = []
        if missing:
            parts.append("missing " + ", ".join(missing))
        if extra:
            parts.append("unknown " + ", ".join(extra))
        raise ContractError("%s fields are invalid: %s" % (label, "; ".join(parts)))
    if any(not values[field] for field in required):
        raise ContractError("%s fields cannot be empty" % label)
    return values


def _module_digests(lines):
    values = {}
    for module_id, digest in _table(lines, ("Module id", "Row digest"), "Module digests"):
        if module_id in values:
            raise ContractError("duplicate module digest: %s" % module_id)
        if not module_id or not DIGEST.fullmatch(digest.strip("` ")):
            raise ContractError("invalid module digest: %s" % module_id)
        values[module_id] = digest.strip("` ")
    return values


def _split_dependencies(value):
    if value == "—":
        return ()
    values = tuple(item.strip().strip("`") for item in value.split(","))
    if not values or any(not item for item in values) or len(set(values)) != len(values):
        raise ContractError("Depends on must be a unique comma-separated module-id list or —")
    return values


def _marker(lines):
    markers = []
    malformed = False
    for line in lines:
        stripped = line.strip()
        match = MARKER.fullmatch(stripped)
        if match:
            markers.append(match)
        elif stripped.startswith("<!-- spec-guard-proposal:"):
            malformed = True
    if malformed or len(markers) != 1:
        raise ContractError("Proposal must contain exactly one complete identity marker")
    return markers[0].group(1), markers[0].group(0)


def _build_order(path):
    matches = []
    for line in _read_visible(path, "capability map"):
        match = BUILD_ORDER.fullmatch(line.strip())
        if match:
            matches.append(match.group(1))
    if len(matches) != 1:
        raise ContractError("capability map must contain exactly one Build order")
    return matches[0]


def parse_proposal(path):
    """Parse the versioned document grammar; no Git or tracker access occurs."""
    lines = _read_visible(path, "Proposal")
    if not lines or not re.fullmatch(r"# Proposal: \S(?:.*\S)?", lines[0].strip()):
        raise ContractError("Proposal title must be the first non-fenced line")
    proposal_id, marker = _marker(lines)
    sections = _sections(lines)
    if not any(line.strip() and not line.lstrip().startswith("|")
               for line in sections["Summary"]):
        raise ContractError("Summary must be non-empty")

    baseline_fields = _field_table(
        sections["Capability map baseline"],
        ("Remote", "Default branch", "Commit", "Capability map", "Goal digest", "Build order"),
        "Capability map baseline")
    if (not re.fullmatch(r"\S+", baseline_fields["Remote"]) or
            not re.fullmatch(r"\S+", baseline_fields["Default branch"]) or
            baseline_fields["Default branch"].startswith("refs/") or
            not COMMIT.fullmatch(baseline_fields["Commit"]) or
            baseline_fields["Capability map"] != "spec/CAPABILITY-MAP.md" or
            not DIGEST.fullmatch(baseline_fields["Goal digest"].strip("`"))):
        raise ContractError("Capability map baseline contains an invalid field value")

    change_fields = _field_table(
        sections["Change"],
        ("Type", "Module id", "Responsibility", "Depends on", "Build-order anchor"),
        "Change")
    if change_fields["Type"] != "new-module":
        raise ContractError("v1 supports only new-module")
    module_id = change_fields["Module id"].strip("`")
    if not MODULE_ID.fullmatch(module_id) or not change_fields["Responsibility"].strip():
        raise ContractError("Change contains an invalid module id or responsibility")
    dependencies = _split_dependencies(change_fields["Depends on"])
    anchor = change_fields["Build-order anchor"].strip("`")
    if anchor != "end" and (not anchor.startswith("after:") or
                            not MODULE_ID.fullmatch(anchor[len("after:"):])):
        raise ContractError("Build-order anchor must be after:<module-id> or end")

    tracker_fields = _field_table(
        sections["Tracker contract"],
        ("Proposal id", "Identity label", "Stage label namespace"),
        "Tracker contract")
    if (tracker_fields["Proposal id"] != proposal_id or
            tracker_fields["Identity label"] != "proposal" or
            tracker_fields["Stage label namespace"] != "proposal-stage:"):
        raise ContractError("Tracker contract does not match the v1 marker and labels")

    return Proposal(proposal_id, marker, Baseline(
        baseline_fields["Remote"], baseline_fields["Default branch"],
        baseline_fields["Commit"], baseline_fields["Goal digest"].strip("`"),
        _module_digests(sections["Capability map baseline"]),
        baseline_fields["Build order"]), Change(module_id, change_fields["Responsibility"],
                                                   dependencies, anchor))


def validate_proposal(path, map_path):
    """Validate a Proposal against caller-supplied capability-map bytes only."""
    proposal = parse_proposal(path)
    try:
        parsed_map = parse_capability_map(str(map_path))
        digest = compute(str(map_path))
    except (MapError, OSError, UnicodeError) as error:
        raise ContractError("invalid capability map: %s" % error)
    expected_digests = dict((item["id"], item["rowDigest"]) for item in digest["rows"])
    if proposal.baseline.goal_digest != digest["goalDigest"]:
        raise ContractError("Goal digest does not match the capability map")
    if proposal.baseline.module_digests != expected_digests:
        raise ContractError("Module digests do not match the capability map")
    if proposal.baseline.build_order != _build_order(map_path):
        raise ContractError("Build order does not match the capability map")
    if proposal.change.module_id in expected_digests:
        raise ContractError("Change module id already exists in the capability map")
    if any(dependency not in expected_digests for dependency in proposal.change.depends_on):
        raise ContractError("Change Depends on contains a module absent from the baseline")
    if proposal.change.anchor == "end":
        anchor_index = len(parsed_map.order)
    else:
        anchor_id = proposal.change.anchor[len("after:"):]
        if anchor_id not in expected_digests:
            raise ContractError("Build-order anchor is absent from the baseline")
        anchor_index = parsed_map.order.index(anchor_id)
    positions = dict((module_id, index) for index, module_id in enumerate(parsed_map.order))
    if any(positions[dependency] > anchor_index for dependency in proposal.change.depends_on):
        raise ContractError("Build-order anchor must not precede a dependency")
    return proposal


def validate_tracker(proposal, issue_body, labels):
    """Validate explicit tracker facts without querying or changing a tracker."""
    lines = _visible_lines(str(issue_body).splitlines())
    if sum(1 for line in lines if line.strip() == proposal.marker) != 1:
        raise ContractError("Issue must contain exactly one complete Proposal marker")
    labels = tuple(str(label) for label in labels)
    if labels.count("proposal") != 1:
        raise ContractError("Issue must contain exactly one proposal identity label")
    stages = [label for label in labels if label.startswith("proposal-stage:")]
    if len(stages) != 1 or stages[0] not in ALLOWED_STAGES:
        raise ContractError("Issue must contain exactly one allowed proposal stage label")
    return True
