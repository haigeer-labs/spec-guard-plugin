#!/usr/bin/env python3
"""Validate and atomically edit an explicitly delimited managed block."""

from __future__ import print_function

import os
import sys
import tempfile


def fail(message):
    print("声明块无效：%s" % message, file=sys.stderr)
    raise SystemExit(1)


def locate(path, begin, end):
    try:
        with open(path, "r", encoding="utf-8", newline="") as handle:
            lines = handle.readlines()
    except OSError as error:
        fail("无法读取 %s：%s" % (path, error))
    begins = [index for index, line in enumerate(lines) if line.strip() == begin]
    ends = [index for index, line in enumerate(lines) if line.strip() == end]
    if len(begins) != 1 or len(ends) != 1:
        fail("BEGIN 和 END 必须各恰好出现一次（当前 %d/%d）" % (len(begins), len(ends)))
    if begins[0] >= ends[0]:
        fail("BEGIN 必须位于 END 之前")
    return lines, begins[0], ends[0]


def atomic_write(path, content):
    directory = os.path.dirname(os.path.abspath(path)) or "."
    mode = os.stat(path).st_mode & 0o777
    descriptor, temporary = tempfile.mkstemp(prefix=".spec-guard-block-", dir=directory)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def main(argv):
    if len(argv) < 5:
        raise SystemExit("usage: managed-block.py <validate|replace|remove> <file> <begin> <end> [template]")
    action, path, begin, end = argv[1:5]
    lines, start, finish = locate(path, begin, end)
    if action == "validate":
        print(finish - start + 1)
        return
    if action == "replace":
        if len(argv) != 6:
            raise SystemExit("replace requires a template path")
        with open(argv[5], "r", encoding="utf-8", newline="") as handle:
            body = handle.readlines()
        if body and not body[-1].endswith(("\n", "\r")):
            body[-1] += "\n"
        atomic_write(path, "".join(lines[: start + 1] + body + lines[finish:]))
        print(finish - start - 1)
        return
    if action == "remove":
        if len(argv) != 5:
            raise SystemExit("remove does not accept a template")
        output = lines[:start] + lines[finish + 1:]
        # Retain the historical one-blank-line normalization, while rejecting
        # malformed input before touching any file.
        while len(output) > start > 0 and output[start - 1].strip() == "" and start < len(output) and output[start].strip() == "":
            del output[start]
        atomic_write(path, "".join(output))
        print(finish - start + 1)
        return
    raise SystemExit("unknown action: %s" % action)


if __name__ == "__main__":
    main(sys.argv)
