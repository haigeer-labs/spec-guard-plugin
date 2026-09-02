#!/usr/bin/env python3
"""Validate and query spec-guard's initiative lifecycle ledger."""
import hashlib
import json
import os
import re
import sys
import tempfile

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
    if value["path"] != prefix:
        fail("artifact path must match checkpoint location")
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

    check_artifact(checkpoint.get("state"), ".agent/history/%s/%s/state.json" % (initiative_id, checkpoint_id))

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


def validate_data(data):
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


def load(path):
    with open(path, encoding="utf-8") as handle:
        return validate_data(json.load(handle))


def write_atomic(path, data):
    directory = os.path.dirname(os.path.abspath(path)) or "."
    if not os.path.isdir(directory):
        fail("ledger directory does not exist")
    descriptor, temporary = tempfile.mkstemp(prefix=".capability-history-", dir=directory)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def create(ledger_path, initiative_path):
    if os.path.exists(ledger_path):
        fail("ledger already exists")
    with open(initiative_path, encoding="utf-8") as handle:
        initiative = json.load(handle)
    check_initiative(initiative)
    write_atomic(ledger_path, {"schemaVersion": 1, "initiatives": [initiative]})


def append(ledger_path, initiative_id, event_path):
    data = load(ledger_path)
    with open(event_path, encoding="utf-8") as handle:
        event = json.load(handle)
    for initiative in data["initiatives"]:
        if initiative["id"] == initiative_id:
            initiative["events"].append(event)
            validate_data(data)
            write_atomic(ledger_path, data)
            return
    fail("initiative not found")


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def verify_artifact(root, artifact):
    if artifact is None:
        return
    path = os.path.realpath(os.path.join(root, artifact["path"]))
    if os.path.commonpath([root, path]) != root:
        fail("artifact resolves outside project root")
    if not os.path.isfile(path):
        fail("history artifact is missing")
    if digest(path) != artifact["sha256"]:
        fail("history artifact digest differs")


def verify(data, root_path):
    root = os.path.realpath(root_path)
    if not os.path.isdir(root):
        fail("project root is not a directory")
    for initiative in data["initiatives"]:
        for event in initiative["events"]:
            checkpoint = event.get("checkpoint")
            if checkpoint is None:
                continue
            verify_artifact(root, checkpoint["map"])
            for module in checkpoint["modules"]:
                verify_artifact(root, module["spec"])
                verify_artifact(root, module["plan"])


def initiative_by_id(data, initiative_id):
    for initiative in data["initiatives"]:
        if initiative["id"] == initiative_id:
            return initiative
    fail("initiative not found")


def paused_checkpoint(data, initiative_id):
    initiative = initiative_by_id(data, initiative_id)
    event = initiative["events"][-1]
    if event["type"] != "paused":
        fail("initiative is not paused")
    return event["checkpoint"]


def active_initiative(data):
    active = [item["id"] for item in data["initiatives"] if item["events"][-1]["type"] in {"created", "resumed"}]
    if len(active) != 1:
        fail("expected exactly one active initiative")
    return active[0]


def verify_checkpoint(data, root_path, initiative_id):
    root = os.path.realpath(root_path)
    if not os.path.isdir(root):
        fail("project root is not a directory")
    checkpoint = paused_checkpoint(data, initiative_id)
    verify_artifact(root, checkpoint["map"])
    verify_artifact(root, checkpoint.get("state"))
    for module in checkpoint["modules"]:
        verify_artifact(root, module["spec"])
        verify_artifact(root, module["plan"])


def main(argv):
    if len(argv) < 2 or argv[0] not in {"validate", "status", "verify", "active", "checkpoint", "verify-checkpoint", "create", "append"}:
        print("usage: capability-history.py validate <file> | status <file> <initiative-id> | verify <file> <project-root> | checkpoint <file> <initiative-id> | verify-checkpoint <file> <project-root> <initiative-id> | create <ledger> <initiative> | append <ledger> <initiative-id> <event>", file=sys.stderr)
        return 2
    try:
        if argv[0] == "create":
            if len(argv) != 3:
                return 2
            create(argv[1], argv[2])
            print("ok")
            return 0
        if argv[0] == "append":
            if len(argv) != 4:
                return 2
            append(argv[1], argv[2], argv[3])
            print("ok")
            return 0
        data = load(argv[1])
        if argv[0] == "validate":
            if len(argv) != 2:
                return 2
            print("ok")
            return 0
        if argv[0] == "verify":
            if len(argv) != 3:
                return 2
            verify(data, argv[2])
            print("ok")
            return 0
        if argv[0] == "checkpoint":
            if len(argv) != 3:
                return 2
            json.dump(paused_checkpoint(data, argv[2]), sys.stdout, ensure_ascii=False)
            sys.stdout.write("\n")
            return 0
        if argv[0] == "active":
            if len(argv) != 2:
                return 2
            print(active_initiative(data))
            return 0
        if argv[0] == "verify-checkpoint":
            if len(argv) != 4:
                return 2
            verify_checkpoint(data, argv[2], argv[3])
            print("ok")
            return 0
        if len(argv) != 3:
            return 2
        initiative = initiative_by_id(data, argv[2])
        print("active" if initiative["events"][-1]["type"] == "created" else initiative["events"][-1]["type"])
        return 0
    except (OSError, json.JSONDecodeError, Invalid) as error:
        print("capability history: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
