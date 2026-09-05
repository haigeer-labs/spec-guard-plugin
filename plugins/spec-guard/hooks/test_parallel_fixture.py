"""Test-only legacy records; never imported by production entry points."""
import json
import os
import subprocess


def write_record(path, record):
    """Construct a fixture without calling the production ledger writer."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(record, handle)
    with open(path, encoding="utf-8") as handle:
        assert json.load(handle) == record, "fixture record was not saved"


def _git(project, *args):
    return subprocess.check_output(
        ["git", "-C", project] + list(args), text=True,
        stderr=subprocess.PIPE).strip()


def verify_fixture_worker(project, manifest):
    """Check the actual worktree, not a production function's success flag."""
    target = manifest["worktreePath"]
    assert os.path.isdir(target), "fixture worktree was not created"
    assert _git(target, "rev-parse", "HEAD") == manifest["baseSha"], "fixture HEAD mismatch"
    assert _git(target, "branch", "--show-current") == manifest["branch"], "fixture branch mismatch"
    registered = _git(project, "worktree", "list", "--porcelain").splitlines()
    assert any(line.startswith("worktree ") and
               os.path.realpath(line[9:]) == os.path.realpath(target)
               for line in registered), "fixture worktree not registered"


def materialize_worker(project, manifest):
    """Prepare an old worker using Git directly, independent of provision()."""
    target = manifest["worktreePath"]
    assert not os.path.lexists(target), "fixture target already exists"
    os.makedirs(os.path.dirname(target), exist_ok=True)
    _git(project, "worktree", "add", "-b", manifest["branch"], target, manifest["baseSha"])
    verify_fixture_worker(project, manifest)
    common = _git(project, "rev-parse", "--git-common-dir")
    if not os.path.isabs(common):
        common = os.path.abspath(os.path.join(project, common))
    write_record(os.path.join(common, "spec-guard", "parallel", "v1", "workers",
                              manifest["workerId"] + ".json"), manifest)
    return dict(manifest)
