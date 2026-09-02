#!/usr/bin/env python3
"""Validate and query spec-guard's initiative lifecycle ledger."""
import json
import re
import sys

ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
CHECKPOINT_ID = re.compile(r"^\d{8}T\d{6}Z-\d{4}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
EVENTS = {"created", "paused", "resumed", "completed", "abandoned", "superseded"}
MODULE_STATUS = {"not-started", "in-progress", "completed", "abandoned", "unknown"}
TERMINAL = {"completed", "abandoned", "superseded"}
NEXT = {
    "created": {"paused", *TERMINAL},
    "paused": {"resumed", "abandoned", "superseded"},
    "resumed": {"paused", *TERMINAL},
}


class Invalid(ValueError):
    pass


def fail(message):
    raise Invalid(message)


def require(value, description):
    if not value:
        fail("missing " + description)
    return value


def check_path(path, prefix):
    if not isinstance(path, str) or path.startswith("/") or ".." in path.split("/"):
        fail("invalid path")
    if not path.startswith(prefix):
        fail("path outside checkpoint")


def check_artifact(value, prefix):
    if value is None:
        return
    if not isinstance(value, dict):
        fail("artifact must be object or null")
    check_path(value.get("path"), prefix)
    if not isinstance(value.get("sha256"), str) or not SHA256.fullmatch(value["sha256"]):
        fail("artifact sha256 must be 64 lowercase hex characters")


def check_checkpoint(checkpoint, initiative_id):
    if not isinstance(checkpoint, dict):
        fail("checkpoint must be an object")
    checkpoint_id = checkpoint.get("id")
    if not isinstance(checkpoint_id, str) or not CHECKPOINT_ID.fullmatch(checkpoint_id):
        fail("invalid checkpoint id")
    base = "spec/history/%s/%s/" % (initiative_id, checkpoint_id)
    map_value = checkpoint.get("map")
    if not isinstance(map_value, dict):
        fail("checkpoint map must be an object")
    check_path(map_value.get("path"), base)
    if map_value.get("path") != base + "CAPABILITY-MAP.md":
        fail("checkpoint map path must be CAPABILITY-MAP.md")
    if not isinstance(map_value.get("sha256"), str) or not SHA256.fullmatch(map_value["sha256"]):
        fail("map sha256 must be 64 lowercase hex characters")

    modules = checkpoint.get("modules")
    if not isinstance(modules, list):
        fail("checkpoint modules must be an array")
    seen = set()
    for module in modules:
        if not isinstance(module, dict):
            fail("module must be an object")
        module_id = module.get("id")
        if not isinstance(module_id, str) or not ID.fullmatch(module_id) or module_id in seen:
            fail("invalid or duplicate module id")
        seen.add(module_id)
        if not isinstance(module.get("responsibility"), str) or not module["responsibility"].strip():
            fail("module responsibility is required")
        depends = module.get("dependsOn")
        if not isinstance(depends, list) or any(not isinstance(item, str) or not ID.fullmatch(item) for item in depends):
            fail("invalid module dependencies")
        if module.get("status") not in MODULE_STATUS:
            fail("invalid module status")
        if module.get("issue") is not None and (not isinstance(module["issue"], int) or module["issue"] < 1):
            fail("invalid module issue")
        check_artifact(module.get("spec"), base + module_id + ".md")
        check_artifact(module.get("plan"), "tasks/history/%s/%s/%s/plan.md" % (initiative_id, checkpoint_id, module_id))


def check_initiative(initiative):
    if not isinstance(initiative, dict):
        fail("initiative must be an object")
    initiative_id = initiative.get("id")
    if not isinstance(initiative_id, str) or not ID.fullmatch(initiative_id):
        fail("invalid initiative id")
    if not isinstance(initiative.get("title"), str) or not initiative["title"].strip():
        fail("initiative title is required")
    events = initiative.get("events")
    if not isinstance(events, list) or not events:
        fail("initiative events are required")
    previous = None
    for index, event in enumerate(events):
        if not isinstance(event, dict) or event.get("type") not in EVENTS:
            fail("invalid lifecycle event")
        event_type = event["type"]
        if index == 0 and event_type != "created":
            fail("first lifecycle event must be created")
        if previous is not None and event_type not in NEXT.get(previous, set()):
            fail("invalid lifecycle transition")
        if event_type in {"created", "paused", *TERMINAL}:
            check_checkpoint(event.get("checkpoint"), initiative_id)
        elif "checkpoint" in event:
            fail("resumed event must not have checkpoint")
        previous = event_type


def load(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict) or data.get("schemaVersion") != 1:
        fail("unsupported capability history schema")
    initiatives = data.get("initiatives")
    if not isinstance(initiatives, list):
        fail("initiatives must be an array")
    ids = set()
    for initiative in initiatives:
        check_initiative(initiative)
        if initiative["id"] in ids:
            fail("duplicate initiative id")
        ids.add(initiative["id"])
    return data


def main(argv):
    if len(argv) < 2 or argv[0] not in {"validate", "status"}:
        print("usage: capability-history.py validate <file> | status <file> <initiative-id>", file=sys.stderr)
        return 2
    try:
        data = load(argv[1])
        if argv[0] == "validate":
            if len(argv) != 2:
                return 2
            print("ok")
            return 0
        if len(argv) != 3:
            return 2
        for initiative in data["initiatives"]:
            if initiative["id"] == argv[2]:
                print("active" if initiative["events"][-1]["type"] == "created" else initiative["events"][-1]["type"])
                return 0
        fail("initiative not found")
    except (OSError, json.JSONDecodeError, Invalid) as error:
        print("capability history: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
