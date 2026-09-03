#!/usr/bin/env python3
"""Produce a conservative, read-only preview of legacy spec-guard evidence."""
import json
import os
import sys
import hashlib
import shutil
import subprocess
import tempfile


def preview(project):
    result = {"candidates": [], "conflicts": []}
    if os.path.exists(os.path.join(project, "spec", "CAPABILITY-HISTORY.json")):
        result["conflicts"].append("capability history ledger already exists")
        return result
    paths = {
        "map": "CAPABILITY-MAP.md",
        "state": ".agent/state.json",
    }
    found = {name: path for name, path in paths.items() if os.path.isfile(os.path.join(project, path))}
    specs = sorted(name for name in os.listdir(project) if name.startswith("SPEC-") and name.endswith(".md")) if os.path.isdir(project) else []
    if not found and not specs:
        return result
    result["candidates"].append({"id": "legacy", "evidence": found, "legacySpecs": specs, "status": "unknown"})
    return result


def main(argv):
    if len(argv) == 2 and argv[0] == "preview":
        print(json.dumps(preview(argv[1]), ensure_ascii=False, sort_keys=True))
        return 0
    if len(argv) == 3 and argv[0] == "import" and argv[1] == "--confirm":
        project = argv[2]
        data = preview(project)
        if data["conflicts"] or not data["candidates"]:
            print("migration refused", file=sys.stderr)
            return 1
        ledger = os.path.join(project, "spec", "CAPABILITY-HISTORY.json")
        map_path = os.path.join(project, "CAPABILITY-MAP.md")
        if not os.path.isfile(map_path):
            print("migration refused", file=sys.stderr)
            return 1
        digest = hashlib.sha256(open(map_path, "rb").read()).hexdigest()
        checkpoint = "19700101T000000Z-0001"
        destination = os.path.join(project, "spec", "history", "legacy", checkpoint)
        if os.path.exists(destination):
            print("migration refused", file=sys.stderr)
            return 1
        record = {"id": "legacy", "title": "Legacy import", "events": [{"type": "created", "at": "imported", "checkpoint": {"id": checkpoint, "map": {"path": "spec/history/legacy/%s/CAPABILITY-MAP.md" % checkpoint, "sha256": digest}, "modules": []}}]}
        try:
            os.makedirs(destination)
            shutil.copyfile(map_path, os.path.join(destination, "CAPABILITY-MAP.md"))
            descriptor, event_path = tempfile.mkstemp(prefix=".history-migration-", dir=project)
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                json.dump(record, handle)
            history = os.path.join(os.path.dirname(__file__), "capability-history.py")
            subprocess.check_call([sys.executable, history, "create", ledger, event_path])
            os.unlink(event_path)
            print("imported legacy")
            return 0
        except (OSError, subprocess.CalledProcessError):
            shutil.rmtree(destination, ignore_errors=True)
            return 1
    else:
        print("usage: history-migration.py preview <project> | import --confirm <project>", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
