"""Summarize declared documentation delivery without asserting content truth."""
import argparse
import json
from pathlib import Path

from documentation_baseline import _visible_lines
from documentation_impact import ImpactError, _cells, _regular, _table, parse_impact


OUTCOMES = frozenset(("delivered", "deferred", "pending"))


class VerificationError(ValueError):
    """The declared documentation outcome cannot safely be interpreted."""


class Outcome(object):
    def __init__(self, concern, outcome, evidence, rationale):
        self.concern = concern
        self.outcome = outcome
        self.evidence = evidence
        self.rationale = rationale


class Verification(object):
    def __init__(self, state, outcomes, attention):
        self.state = state
        self.outcomes = outcomes
        self.attention = attention


def _empty(value):
    value = value.strip().strip("`").strip()
    return None if value in ("", "-", "—") else value


def _has_outcome_table(path):
    try:
        lines = _visible_lines(path.read_text(encoding="utf-8").splitlines())
    except (OSError, UnicodeError) as error:
        raise VerificationError("cannot read module plan: %s" % error)
    headers = ["concern", "outcome", "evidence", "rationale"]
    return sum(1 for line in lines if _cells(line) and
               [cell.lower() for cell in _cells(line)] == headers)


def _outcomes(path, required):
    count = _has_outcome_table(path)
    if count == 0:
        return {}
    if count != 1:
        raise VerificationError("module plan must contain exactly one Documentation outcome table")
    entries = {}
    for concern, outcome, evidence, rationale in _table(
            _regular(path, "module plan"),
            ("Concern", "Outcome", "Evidence", "Rationale"), "Documentation outcome"):
        if concern in entries:
            raise VerificationError("duplicate outcome concern: %s" % concern)
        if concern not in required:
            raise VerificationError("outcome is only allowed for update/create: %s" % concern)
        if outcome not in OUTCOMES:
            raise VerificationError("unknown outcome: %s" % outcome)
        evidence = _empty(evidence)
        if outcome == "delivered" and evidence is None:
            raise VerificationError("delivered outcome requires evidence for %s" % concern)
        if not rationale:
            raise VerificationError("outcome rationale is required for %s" % concern)
        entries[concern] = Outcome(concern, outcome, evidence, rationale)
    return entries


def verify_documentation(project, module):
    """Return conservative declared-document facts for a module."""
    project = Path(project)
    try:
        impact = parse_impact(project, module)
    except ImpactError as error:
        raise VerificationError(str(error))
    if impact.state == "absent":
        return Verification("absent", {}, [])
    required = set(concern for concern, decision in impact.decisions.items()
                   if decision.decision in ("update", "create"))
    plan = project / "tasks" / module / "plan.md"
    outcomes = _outcomes(plan, required)
    attention = []
    for concern, decision in sorted(impact.decisions.items()):
        if decision.decision == "pending":
            attention.append("%s has a pending documentation decision" % concern)
    for concern in sorted(required):
        outcome = outcomes.get(concern)
        if outcome is None:
            attention.append("%s has no declared documentation outcome" % concern)
        elif outcome.outcome != "delivered":
            attention.append("%s is declared %s" % (concern, outcome.outcome))
    return Verification("attention" if attention else "ready", outcomes, attention)


def _as_json(result):
    return {
        "state": result.state,
        "outcomes": dict((concern, {
            "outcome": item.outcome,
            "evidence": item.evidence,
            "rationale": item.rationale,
        }) for concern, item in sorted(result.outcomes.items())),
        "attention": result.attention,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    parser.add_argument("--module", required=True)
    parser.add_argument("--format", choices=("json",), default="json")
    args = parser.parse_args(argv)
    try:
        result = verify_documentation(args.project, args.module)
    except (VerificationError, OSError, UnicodeError) as error:
        print(json.dumps({"state": "invalid", "error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(_as_json(result), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
