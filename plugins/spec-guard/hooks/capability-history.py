#!/usr/bin/env python3
"""Validate and query spec-guard's initiative lifecycle ledger."""
import hashlib
import json
import os
import re
import sys
import tempfile

from capability_map import MapError, parse_map

ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
CHECKPOINT_ID = re.compile(r"^\d{8}T\d{6}Z-\d{4}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
AUDIT_TIME = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
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


def check_correction(correction, initiatives):
    if not isinstance(correction, dict) or correction.get("type") != "history-correction":
        fail("invalid history correction")
    initiative_id = correction.get("initiativeId")
    if initiative_id not in initiatives:
        fail("correction initiative not found")
    event_index = correction.get("eventIndex")
    events = initiatives[initiative_id]["events"]
    if not isinstance(event_index, int) or isinstance(event_index, bool) or not 0 <= event_index < len(events):
        fail("invalid correction event index")
    checkpoint = events[event_index].get("checkpoint")
    checkpoint_id = correction.get("checkpointId")
    expected_checkpoint_id = checkpoint["id"] if checkpoint else None
    if checkpoint_id != expected_checkpoint_id:
        fail("correction checkpoint does not match event")
    module_id = correction.get("moduleId")
    field = correction.get("field")
    if field not in {"responsibility", "dependsOn", "status", "event.at"}:
        fail("invalid correction field")
    if field == "event.at":
        if module_id is not None:
            fail("event time correction must not name a module")
    elif checkpoint is None:
        fail("module correction requires a checkpoint")
    elif (not isinstance(module_id, str) or not ID.fullmatch(module_id) or
          module_id not in {module["id"] for module in checkpoint["modules"]}):
        fail("module correction requires a valid module id")
    if not AUDIT_TIME.fullmatch(correction.get("auditedAt", "")):
        fail("invalid correction audit time")
    if not isinstance(correction.get("auditReportSha256"), str) or not SHA256.fullmatch(correction["auditReportSha256"]):
        fail("invalid correction audit report digest")
    if "before" not in correction or "after" not in correction:
        fail("correction before and after are required")
    if field == "responsibility":
        if not all(isinstance(correction[key], str) and correction[key].strip()
                   for key in ("before", "after")):
            fail("responsibility correction values are invalid")
    elif field == "dependsOn":
        if any(not isinstance(correction[key], list) or
               any(not isinstance(item, str) or not ID.fullmatch(item) for item in correction[key])
               for key in ("before", "after")):
            fail("dependency correction values are invalid")
    elif field == "status":
        if correction["before"] not in MODULE_STATUS or correction["after"] != "unknown":
            fail("status correction must retain unknown")
    elif not isinstance(correction["before"], str) or correction["after"] != "unknown":
        fail("event time correction must retain unknown")
    sources = correction.get("sources")
    if not isinstance(sources, list) or not sources:
        fail("correction sources are required")
    for source in sources:
        if (not isinstance(source, dict) or source.get("kind") != "audit-finding" or
                not isinstance(source.get("code"), str) or not source["code"]):
            fail("invalid correction source")


def correction_identity(item, before_key, after_key):
    return (tuple(item.get(key) for key in
                  ("initiativeId", "eventIndex", "checkpointId", "moduleId", "field")) +
            (json.dumps(item.get(before_key), ensure_ascii=False, sort_keys=True),
             json.dumps(item.get(after_key), ensure_ascii=False, sort_keys=True)))


def validate_data(data):
    if not isinstance(data, dict) or data.get("schemaVersion") != 1:
        fail("unsupported capability history schema")
    initiatives = data.get("initiatives")
    if not isinstance(initiatives, list):
        fail("initiatives must be an array")
    initiatives_by_id = {}
    for initiative in initiatives:
        check_initiative(initiative)
        if initiative["id"] in initiatives_by_id:
            fail("duplicate initiative id")
        initiatives_by_id[initiative["id"]] = initiative
    corrections = data.get("corrections", [])
    if not isinstance(corrections, list):
        fail("corrections must be an array")
    for correction in corrections:
        check_correction(correction, initiatives_by_id)
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


def ensure(ledger_path, initiative_path):
    with open(initiative_path, encoding="utf-8") as handle:
        initiative = json.load(handle)
    check_initiative(initiative)
    if not os.path.exists(ledger_path):
        write_atomic(ledger_path, {"schemaVersion": 1, "initiatives": [initiative]})
        return
    data = load(ledger_path)
    if any(item["id"] == initiative["id"] for item in data["initiatives"]):
        return
    data["initiatives"].append(initiative)
    validate_data(data)
    write_atomic(ledger_path, data)


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
            verify_artifact(root, checkpoint.get("state"))
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


def audit(data, root_path):
    """Report semantic history claims that cannot be established from evidence.

    This is deliberately independent from ``verify``: a digest proves that a
    checkpoint file was preserved, not that fields copied into the ledger are
    faithful to its contents or that a status/timestamp has external support.
    """
    root = os.path.realpath(root_path)
    if not os.path.isdir(root):
        fail("project root is not a directory")
    findings = []
    corrections = {}
    for index, correction in enumerate(data.get("corrections", [])):
        corrections[correction_identity(correction, "before", "after")] = index

    def report(initiative, event_index, checkpoint, field, code, message,
               module=None, expected=None, actual=None):
        item = {
            "initiativeId": initiative["id"],
            "eventIndex": event_index,
            "field": field,
            "code": code,
            "message": message,
        }
        if checkpoint is not None:
            item["checkpointId"] = checkpoint["id"]
        if module is not None:
            item["moduleId"] = module["id"]
        if expected is not None:
            item["expected"] = expected
        if actual is not None:
            item["actual"] = actual
        findings.append(item)

    for initiative in data["initiatives"]:
        for event_index, event in enumerate(initiative["events"]):
            checkpoint = event.get("checkpoint")
            if event.get("at"):
                report(initiative, event_index, checkpoint, "event.at",
                       "timestamp-unverified",
                       "ledger event time has no recorded source evidence",
                       expected="unknown", actual=event["at"])
            if checkpoint is None:
                continue
            map_artifact = checkpoint["map"]
            map_path = os.path.realpath(os.path.join(root, map_artifact["path"]))
            rows = None
            if not os.path.isfile(map_path):
                report(initiative, event_index, checkpoint, "checkpoint.map",
                       "map-missing", "checkpointed capability map is missing")
            elif digest(map_path) != map_artifact["sha256"]:
                report(initiative, event_index, checkpoint, "checkpoint.map",
                       "map-digest-differs",
                       "checkpointed capability map digest differs")
            else:
                try:
                    rows = dict((row.module_id, row) for row in parse_map(map_path).rows)
                except (OSError, MapError) as error:
                    report(initiative, event_index, checkpoint, "checkpoint.map",
                           "map-unparseable", "checkpointed capability map is unusable: %s" % error)

            for module in checkpoint["modules"]:
                if rows is not None:
                    source = rows.get(module["id"])
                    if source is None:
                        report(initiative, event_index, checkpoint, "module",
                               "module-missing-from-map",
                               "ledger module is absent from checkpointed capability map", module)
                    else:
                        if module["responsibility"] != source.responsibility:
                            report(initiative, event_index, checkpoint, "responsibility",
                                   "responsibility-mismatch",
                                   "ledger responsibility differs from checkpointed capability map",
                                   module, source.responsibility, module["responsibility"])
                        if module["dependsOn"] != source.depends_on:
                            report(initiative, event_index, checkpoint, "dependsOn",
                                   "dependency-mismatch",
                                   "ledger dependencies differ from checkpointed capability map",
                                   module, source.depends_on, module["dependsOn"])
                if module["status"] != "unknown":
                    report(initiative, event_index, checkpoint, "status",
                           "status-unsupported",
                           "checkpoint state and Issue identity do not prove module status; retain unknown",
                           module, "unknown", module["status"])

    counts = {}
    unresolved_counts = {}
    corrected = 0
    for finding in findings:
        counts[finding["code"]] = counts.get(finding["code"], 0) + 1
        correction_index = corrections.get(correction_identity(finding, "actual", "expected"))
        if correction_index is None:
            finding["resolution"] = "unresolved"
            unresolved_counts[finding["code"]] = unresolved_counts.get(finding["code"], 0) + 1
        else:
            finding["resolution"] = "corrected"
            finding["correctionIndex"] = correction_index
            corrected += 1
    return {"schemaVersion": 1, "readOnly": True, "findings": findings,
            "summary": {"findings": len(findings), "byCode": counts,
                        "correctedFindings": corrected,
                        "unresolvedFindings": len(findings) - corrected,
                        "unresolvedByCode": unresolved_counts}}


def load_json(path, description):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        fail("invalid %s: %s" % (description, error))


def find_audit_finding(report, correction):
    if report.get("schemaVersion") != 1 or report.get("readOnly") is not True:
        fail("invalid audit report")
    for finding in report.get("findings", []):
        if not isinstance(finding, dict):
            continue
        same_identity = all(finding.get(key) == correction.get(key)
                            for key in ("initiativeId", "eventIndex", "checkpointId", "moduleId", "field"))
        if same_identity and finding.get("actual") == correction["before"] and finding.get("expected") == correction["after"]:
            return finding
    fail("correction does not match an audit finding")


def append_correction(ledger_path, audit_path, correction_path):
    data = load(ledger_path)
    report = load_json(audit_path, "audit report")
    correction = load_json(correction_path, "correction")
    if not isinstance(correction, dict):
        fail("invalid correction")
    initiatives = {item["id"]: item for item in data["initiatives"]}
    check_correction(correction, initiatives)
    if correction.get("auditReportSha256") != digest(audit_path):
        fail("correction audit report digest differs")
    finding = find_audit_finding(report, correction)
    codes = {source["code"] for source in correction.get("sources", [])
             if isinstance(source, dict) and source.get("kind") == "audit-finding"}
    if finding["code"] not in codes:
        fail("correction source does not cite audit finding")
    corrections = data.setdefault("corrections", [])
    if correction in corrections:
        fail("correction already recorded")
    corrections.append(correction)
    validate_data(data)
    write_atomic(ledger_path, data)


def main(argv):
    if len(argv) < 2 or argv[0] not in {"validate", "status", "verify", "audit", "correct", "active", "checkpoint", "verify-checkpoint", "create", "ensure", "append"}:
        print("usage: capability-history.py validate <file> | status <file> <initiative-id> | verify <file> <project-root> | audit <file> <project-root> | correct --confirm <ledger> <audit-report> <correction> | checkpoint <file> <initiative-id> | verify-checkpoint <file> <project-root> <initiative-id> | create <ledger> <initiative> | ensure <ledger> <initiative> | append <ledger> <initiative-id> <event>", file=sys.stderr)
        return 2
    try:
        if argv[0] == "correct":
            if len(argv) != 5 or argv[1] != "--confirm":
                return 2
            append_correction(argv[2], argv[3], argv[4])
            print("ok")
            return 0
        if argv[0] == "create":
            if len(argv) != 3:
                return 2
            create(argv[1], argv[2])
            print("ok")
            return 0
        if argv[0] == "ensure":
            if len(argv) != 3:
                return 2
            ensure(argv[1], argv[2])
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
        if argv[0] == "audit":
            if len(argv) != 3:
                return 2
            json.dump(audit(data, argv[2]), sys.stdout, ensure_ascii=False, sort_keys=True)
            sys.stdout.write("\n")
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
