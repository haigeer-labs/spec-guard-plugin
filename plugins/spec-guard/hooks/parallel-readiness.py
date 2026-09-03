#!/usr/bin/env python3
"""只读地列出能力图中值得进入安全审查的并行候选。"""
from __future__ import print_function

import argparse
import json
import os
import subprocess
import sys

from capability_map import MapError, parse_map


def git(project, *args):
    result = subprocess.run(
        ["git", "-C", project] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(detail or "git 命令失败")
    return result.stdout.strip()


def default_base(project):
    ref = git(project, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    sha = git(project, "rev-parse", ref)
    if len(sha) != 40:
        raise RuntimeError("默认分支没有可解析的完整 commit SHA")
    return ref, sha


def refreshed_base(project):
    ref, _ = default_base(project)
    branch = ref.split("/", 1)[1]
    git(project, "fetch", "--quiet", "origin", branch)
    return default_base(project)


def candidate_groups(parsed):
    rows = dict((row.module_id, row) for row in parsed.rows)
    layers = {}
    for module_id in parsed.order:
        dependencies = rows[module_id].depends_on
        layers[module_id] = 0 if not dependencies else max(
            layers[dependency] for dependency in dependencies
        ) + 1

    grouped = {}
    for module_id in parsed.order:
        grouped.setdefault(layers[module_id], []).append(module_id)
    return [
        {
            "layer": layer,
            "modules": modules,
            "classification": "candidate-only",
        }
        for layer, modules in sorted(grouped.items())
        if len(modules) >= 2
    ]


def report(project, refresh=False):
    map_path = os.path.join(project, "spec", "CAPABILITY-MAP.md")
    parsed = parse_map(map_path)
    ref, sha = refreshed_base(project) if refresh else default_base(project)
    return {
        "ok": True,
        "base": {"ref": ref, "sha": sha, "fresh": refresh},
        "candidateGroups": candidate_groups(parsed),
        "warnings": [] if refresh else [
            "尚未验证远端新鲜度；传 --refresh 后才可称为最新主线。"
        ],
    }


def text_report(data):
    base = data["base"]
    lines = [
        "并行开发候选分析（不是安全并行判定）",
        "基线: %s @ %s" % (base["ref"], base["sha"]),
        "新鲜度: 已验证" if base["fresh"] else "新鲜度: 未验证",
    ]
    if data["candidateGroups"]:
        lines.append("候选组:")
        for group in data["candidateGroups"]:
            lines.append("- layer %s: %s [%s]" % (
                group["layer"], ", ".join(group["modules"]), group["classification"]
            ))
    else:
        lines.append("没有至少两个模块的同层候选组。")
    lines.extend("警告: %s" % warning for warning in data["warnings"])
    return "\n".join(lines)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args(argv)
    try:
        data = report(os.path.abspath(args.project), refresh=args.refresh)
    except (MapError, OSError, RuntimeError) as error:
        print("parallel-readiness: %s" % error, file=sys.stderr)
        return 1

    if args.format == "json":
        print(json.dumps(data, ensure_ascii=False, sort_keys=True))
    else:
        print(text_report(data))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
