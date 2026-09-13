#!/usr/bin/env python3
"""Validate release evidence without treating weaker observations as stronger."""
import json
import re
import sys


VERSION = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")
TIMESTAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
VERIFIED_TARGETS = {
    "source-verified": "source-checkout",
    "package-verified": "package",
    "installed-verified": "installed-session",
    "host-verified": "host-session",
    "project-verified": "tracker-project",
}
UNVERIFIED = {"not-verified", "unsupported"}
JOURNEY_TARGETS = {
    "github-project": ("project-verified", "tracker-project"),
    "gitlab-project": ("project-verified", "tracker-project"),
    "manual-worktrees": ("host-verified", "worktree-pair"),
    "fresh-install": ("installed-verified", "installed-session"),
    "degraded-environment": (None, "environment"),
}


class Invalid(ValueError):
    pass


def fail(message):
    raise Invalid(message)


def nonempty(value, name):
    if not isinstance(value, str) or not value.strip():
        fail("invalid " + name)
    return value


def check_target(target):
    if not isinstance(target, dict):
        fail("target is required")
    return nonempty(target.get("kind"), "target kind"), nonempty(target.get("id"), "target id")


def check_record(record):
    if not isinstance(record, dict):
        fail("record must be an object")
    nonempty(record.get("subject"), "subject")
    status = record.get("status")
    target_kind, _ = check_target(record.get("target"))
    capabilities = record.get("capabilities", [])
    if not isinstance(capabilities, list) or any(not isinstance(item, str) for item in capabilities):
        fail("invalid capabilities")
    if status in VERIFIED_TARGETS:
        if target_kind != VERIFIED_TARGETS[status]:
            fail("evidence status does not match target kind")
        if not TIMESTAMP.fullmatch(record.get("observedAt", "")):
            fail("verified evidence requires an observation time")
        evidence = record.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            fail("verified evidence requires references")
        for item in evidence:
            nonempty(item, "evidence reference")
        return
    if status in UNVERIFIED:
        nonempty(record.get("reason"), "unverified reason")
        if "observedAt" in record or "evidence" in record:
            fail("unverified evidence must not claim an observation")
        return
    fail("invalid evidence status")


def check_journey(journey):
    if not isinstance(journey, dict):
        fail("journey must be an object")
    nonempty(journey.get("id"), "journey id")
    kind = journey.get("kind")
    if kind not in JOURNEY_TARGETS:
        fail("invalid journey kind")
    if journey.get("confirmation") != "required":
        fail("real acceptance journeys require confirmation")
    target_kind, _ = check_target(journey.get("target"))
    expected_status, expected_target = JOURNEY_TARGETS[kind]
    if target_kind != expected_target:
        fail("journey target does not match its kind")
    effects = journey.get("expectedSideEffects")
    if not isinstance(effects, list) or not effects:
        fail("journey requires expected side effects")
    for effect in effects:
        nonempty(effect, "expected side effect")

    status = journey.get("status")
    if status in UNVERIFIED:
        nonempty(journey.get("reason"), "unverified journey reason")
        if "observedAt" in journey or "evidence" in journey:
            fail("unverified journey must not claim an observation")
        return

    if expected_status is None or status != expected_status:
        fail("journey status does not match its target")
    if not TIMESTAMP.fullmatch(journey.get("observedAt", "")):
        fail("verified journey requires an observation time")
    evidence = journey.get("evidence")
    if not isinstance(evidence, list) or not evidence:
        fail("verified journey requires references")
    for item in evidence:
        nonempty(item, "journey evidence reference")


def validate(data):
    if not isinstance(data, dict) or data.get("schemaVersion") != 1:
        fail("unsupported release evidence schema")
    release = data.get("release")
    if not isinstance(release, dict) or not VERSION.fullmatch(release.get("version", "")):
        fail("invalid release version")
    records = data.get("records")
    if not isinstance(records, list) or not records:
        fail("records are required")
    seen = set()
    for record in records:
        check_record(record)
        key = (record["subject"], record["target"]["kind"], record["target"]["id"])
        if key in seen:
            fail("duplicate evidence record")
        seen.add(key)
    journeys = data.get("journeys", [])
    if not isinstance(journeys, list):
        fail("invalid journeys")
    journey_ids = set()
    for journey in journeys:
        check_journey(journey)
        if journey["id"] in journey_ids:
            fail("duplicate journey id")
        journey_ids.add(journey["id"])


def main(argv):
    if len(argv) != 2 or argv[0] != "validate":
        print("usage: release-evidence.py validate <record.json>", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            validate(json.load(handle))
        print("ok")
        return 0
    except (OSError, json.JSONDecodeError, Invalid) as error:
        print("release evidence: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
