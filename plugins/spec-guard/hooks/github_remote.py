"""GitHub origin-URL parsing shared by initiative-lifecycle.sh.

Single source of truth for turning a `git remote get-url origin` value into
an `owner/repo` identity. Host classification (``remote_host`` /
``is_github_remote``) must stay byte-for-byte compatible with the bash
copies in phase-guard.sh and verify-artifacts.sh — see
test-github-remote-parity.sh, which checks all three agree.
"""
import re

SEGMENT_RE = re.compile(r"[A-Za-z0-9_.-]+")


def remote_host(url):
    """Extract the host (or scp-like alias) segment from a remote URL."""
    host = url
    if "://" in host:
        host = host.split("://", 1)[1]
    if "@" in host:
        host = host.split("@", 1)[1]
    host = host.split("/", 1)[0]
    host = host.split(":", 1)[0]
    return host


def is_github_remote(url):
    """True when the remote's host segment contains "github"."""
    return "github" in remote_host(url)


def repository_from_remote(remote):
    """Return "owner/repo" for a GitHub remote URL, or None.

    Supports https(s)://, git@host:owner/repo (scp-like with a user), and
    a bare host-alias scp-like form without a user (`alias:owner/repo`) —
    accepted only when there is no "://", the part before the first ":"
    contains no "/", and that part is a GitHub host. Trailing slashes and
    a case-insensitive ".git" suffix are stripped.
    """
    if not remote or not is_github_remote(remote):
        return None

    if "://" in remote:
        path = remote.split("://", 1)[1]
        path = path.split("/", 1)[1] if "/" in path else ""
    else:
        at_index = remote.find("@")
        colon_index = remote.find(":", at_index) if at_index != -1 else -1
        if at_index != -1 and colon_index != -1:
            path = remote.split(":", 1)[1]
        else:
            # scp-like alias without a user (`alias:owner/repo`). Only
            # treat this as host:path when the prefix before the first
            # ":" has no "/" in it (a bare host/alias, not e.g. a local
            # filesystem path that happens to contain a colon later) and
            # that prefix is itself a GitHub host.
            colon_index = remote.find(":")
            if colon_index == -1:
                return None
            host_part = remote[:colon_index]
            if "/" in host_part or "github" not in host_part:
                return None
            path = remote[colon_index + 1:]

    if path.startswith("/"):
        path = path[1:]
    path = path.rstrip("/")
    if path.lower().endswith(".git"):
        path = path[: -len(".git")]
    path = path.rstrip("/")

    if "/" not in path:
        return None
    owner, repository = path.split("/", 1)
    if not SEGMENT_RE.fullmatch(owner):
        return None
    if "/" in repository or not SEGMENT_RE.fullmatch(repository):
        return None
    return "%s/%s" % (owner, repository)
