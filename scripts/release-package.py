#!/usr/bin/env python3
"""Verify a named Spec Guard release artifact, never a source checkout."""
import json
import os
import sys


REQUIRED = (
    ".claude-plugin/marketplace.json",
    "plugins/spec-guard/.claude-plugin/plugin.json",
    "plugins/spec-guard/.codex-plugin/plugin.json",
    "plugins/spec-guard/manifest.json",
)


class Invalid(ValueError):
    pass


def fail(message):
    raise Invalid(message)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def validate(root, expected_version):
    root = os.path.realpath(root)
    if not os.path.isdir(root):
        fail("artifact directory is missing")
    if os.path.exists(os.path.join(root, ".git")):
        fail("source checkout is not a release artifact")
    manifest_path = os.path.join(root, "ARTIFACT-MANIFEST.json")
    artifact = load(manifest_path)
    if (not isinstance(artifact, dict) or artifact.get("schemaVersion") != 1 or
            artifact.get("artifactKind") != "spec-guard-plugin" or
            artifact.get("version") != expected_version):
        fail("artifact manifest identity differs")
    files = artifact.get("files")
    if not isinstance(files, list) or set(files) != set(REQUIRED):
        fail("artifact manifest file list differs")
    for relative in REQUIRED:
        if not os.path.isfile(os.path.join(root, relative)):
            fail("artifact file is missing: " + relative)
    marketplace = load(os.path.join(root, REQUIRED[0]))
    plugins = marketplace.get("plugins") if isinstance(marketplace, dict) else None
    if (not isinstance(plugins, list) or len(plugins) != 1 or
            plugins[0].get("name") != "spec-guard" or
            plugins[0].get("source") != "./plugins/spec-guard"):
        fail("marketplace projection differs")
    for relative in REQUIRED[1:]:
        manifest = load(os.path.join(root, relative))
        if manifest.get("name") != "spec-guard" or manifest.get("version") != expected_version:
            fail("plugin manifest identity differs: " + relative)


def main(argv):
    if len(argv) != 3 or argv[0] != "validate":
        print("usage: release-package.py validate <artifact-dir> <version>", file=sys.stderr)
        return 2
    try:
        validate(argv[1], argv[2])
        print("ok")
        return 0
    except (OSError, json.JSONDecodeError, Invalid) as error:
        print("release package: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
