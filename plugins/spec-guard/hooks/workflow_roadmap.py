"""Collect and render conservative, read-only workflow-roadmap facts."""
from __future__ import print_function

import json
import argparse
from pathlib import Path
import re
import subprocess
import sys

from capability_map import parse_map


CHECKPOINT = re.compile(r"^#{2,3}\s*Checkpoint:\s*(.+?)\s*$", re.IGNORECASE)
NEXT_STEP = re.compile(r"^\*\*(?:Next step:|下一步：)\*\*\s*(.+?)\s*$", re.IGNORECASE)


def _run(root, *args):
    try:
        return subprocess.check_output(["git", "-C", str(root)] + list(args),
                                       stderr=subprocess.DEVNULL,
                                       text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def _git_facts(root):
    top = _run(root, "rev-parse", "--show-toplevel")
    if not top:
        return {"evidence": "?", "kind": "unknown", "root": None,
                "position": "unknown", "head": None, "dirty": "unknown"}
    top = Path(top).resolve()
    entries = [line.split(" ", 1)[1] for line in
               (_run(top, "worktree", "list", "--porcelain") or "").splitlines()
               if line.startswith("worktree ")]
    kind = "primary" if entries and Path(entries[0]).resolve() == top else "linked"
    branch = _run(top, "symbolic-ref", "--quiet", "--short", "HEAD")
    short = _run(top, "rev-parse", "--short", "HEAD")
    position = branch or ("HEAD（detached @ %s）" % short if short else "detached HEAD")
    status = _run(top, "status", "--porcelain")
    return {"evidence": "✓", "kind": kind, "root": str(top), "position": position,
            "head": short, "dirty": 0 if status == "" else len((status or "").splitlines())}


def _checkpoint(plan):
    if not plan.is_file():
        return {"evidence": "?", "name": None, "condition": "计划不存在"}
    for line in plan.read_text(encoding="utf-8").splitlines():
        match = CHECKPOINT.match(line)
        if match:
            return {"evidence": "~", "name": match.group(1),
                    "condition": "计划声明；是否已通过尚未验证"}
    return {"evidence": "?", "name": None, "condition": "计划未声明结构化 Checkpoint"}


def _next_action(plan):
    if not plan.is_file():
        return {"evidence": "?", "detail": "Plan 不存在，下一行动未知"}
    for line in plan.read_text(encoding="utf-8").splitlines():
        match = NEXT_STEP.match(line)
        if match:
            return {"evidence": "~", "detail": match.group(1)}
    return {"evidence": "?", "detail": "Plan 未声明下一行动"}


def _run_remote(command, root):
    return subprocess.run(command, cwd=str(root), capture_output=True, text=True, timeout=5)


def _github_credential_access_failed(result):
    error = getattr(result, "stderr", "") or ""
    normalized = error.lower()
    return any(marker in normalized for marker in (
        "failed to log in",
        "not logged in",
        "token in default is invalid",
        "gh auth login",
        "keychain",
    ))


def _github_api_network_unavailable(result):
    error = getattr(result, "stderr", "") or ""
    normalized = error.lower()
    return ("error connecting to api.github.com" in normalized or
            "failed to connect to api.github.com" in normalized)


def _github_remote(root, state, module):
    mappings = state.get("modules")
    entry = mappings.get(module, {}) if isinstance(mappings, dict) else {}
    issue = entry.get("issue") if isinstance(entry, dict) else None
    if not isinstance(issue, int) or issue <= 0:
        return "unknown", "GitHub 模块 Issue 未声明"
    try:
        result = _run_remote(["gh", "issue", "view", str(issue), "--json", "state,subIssues"], root)
        data = json.loads(result.stdout) if result.returncode == 0 else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        result = None
        data = None
    if not isinstance(data, dict):
        if result is not None and _github_credential_access_failed(result):
            return "unknown", (
                "GitHub CLI 认证或凭据访问不可用；请在可访问凭据的 shell 中检查 "
                "gh auth status，并按其结果重新认证后重试"
            )
        if result is not None and _github_api_network_unavailable(result):
            return "unknown", (
                "GitHub API 网络访问不可用；请检查当前 shell 的网络或沙箱权限后重试"
            )
        return "unknown", "GitHub 只读查询不可用"
    children = data.get("subIssues")
    count = children.get("totalCount") if isinstance(children, dict) else None
    detail = "GitHub Issue #%s: %s" % (issue, data.get("state", "状态未知"))
    if isinstance(count, int):
        detail += "；sub-issue 数=%s（不是进度分母）" % count
    return "verified", detail


def _empty(problem):
    return {"ok": False, "currentModule": None, "dependencies": [], "successors": [],
            "mode": "unknown", "remote": "unknown", "checkpoint": _checkpoint(Path("/nonexistent")),
            "nextAction": _next_action(Path("/nonexistent")),
            "specExists": False, "planExists": False,
            "remoteDetail": "远端事实未知", "initiative": None, "modules": [],
            "git": _git_facts(Path.cwd()), "problems": [problem]}


def collect(project):
    """Return only facts derivable from local state, map, plan and Git."""
    root = Path(project).resolve()
    state_path = root / ".agent/state.json"
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return _empty("initiative state is missing or unreadable")
    initiative = state.get("initiative")
    if not isinstance(initiative, dict) or not isinstance(initiative.get("title"), str) or not initiative["title"].strip():
        return _empty("initiative identity is missing or invalid")
    map_name = initiative.get("map")
    if not isinstance(map_name, str) or not map_name or Path(map_name).is_absolute():
        return _empty("initiative map identity is missing or unsafe")
    map_path = (root / map_name).resolve()
    try:
        map_path.relative_to(root)
        parsed = parse_map(map_path)
    except (OSError, ValueError):
        return _empty("initiative map is unreadable or invalid")
    module = state.get("activeModule")
    if not isinstance(module, str) or module not in parsed.order:
        return _empty("initiative active module is missing or not in the active map")
    rows = dict((row.module_id, row) for row in parsed.rows)
    dependencies = list(rows[module].depends_on)
    successors = [row.module_id for row in parsed.rows if module in row.depends_on]
    plan = root / "tasks" / module / "plan.md"
    mode = state.get("workflowStage") or "tracker-active"
    if mode == "local-validation":
        remote = "not-applicable"
        remote_detail = "本地验证阶段不查询 tracker"
    elif state.get("tracker") == "github":
        remote, remote_detail = _github_remote(root, state, module)
    else:
        remote = "unknown"
        remote_detail = "当前 tracker 没有可安全读取的路线图事实"
    problems = []
    spec_exists = (root / "spec" / (module + ".md")).is_file()
    if not spec_exists:
        problems.append("! 当前模块缺少 Spec")
    plan_exists = plan.is_file()
    if not plan_exists:
        problems.append("! 当前模块缺少 Plan")
    return {
        # Identity remains established even when a downstream artifact is absent.
        # The renderer must show that chain break in context, not erase the location.
        "ok": True,
        "initiative": {"title": initiative["title"], "map": map_name, "evidence": "✓"},
        "currentModule": module,
        "dependencies": dependencies,
        "successors": successors,
        "mode": mode,
        "remote": remote,
        "remoteDetail": remote_detail,
        "checkpoint": _checkpoint(plan),
        "nextAction": _next_action(plan),
        "specExists": spec_exists,
        "planExists": plan_exists,
        "modules": [{"id": row.module_id, "dependsOn": list(row.depends_on)} for row in parsed.rows],
        "git": _git_facts(root),
        "problems": problems,
    }


def _join(values):
    return "、".join(values) if values else "无"


def _artifact_position(label, exists):
    return "%s（%s）" % (label, "✓ 产物存在" if exists else "! 产物缺失")


def render(facts, all_modules=False):
    """Render facts without converting declarations or unknowns into completion."""
    if not facts["ok"]:
        return "路线图不可判定\n\n" + "\n".join("! " + item for item in facts["problems"])
    initiative = facts["initiative"]
    git = facts["git"]
    lines = [
        "正常工作流（agent-skills）",
        "  Phase 0 能力图（可选） → Specify → Plan → Tasks → Implement → Test/Review/Ship",
        "  Spec Guard 扩展：tracker 激活后才显示模块 Issue/PR/MR 交付。",
        "",
        "Initiative",
        "  身份: %s" % initiative["title"],
        "  活跃能力图: %s（%s 已验证）" % (initiative["map"], initiative["evidence"]),
        "",
        "当前位置",
        "  当前模块: %s" % facts["currentModule"],
        "  模块链路位置: %s → %s → Tasks → Implement → Test/Review/Ship（? 无统一可验证事实）" % (
            _artifact_position("Specify", facts["specExists"]),
            _artifact_position("Plan", facts["planExists"])),
        "  直接依赖: %s" % _join(facts["dependencies"]),
        "  直接后继: %s" % _join(facts["successors"]),
        "  工作模式: %s" % facts["mode"],
        "  远端事实: %s" % ({
            "not-applicable": "远端任务、同步和交付均不适用",
            "verified": "✓ " + facts["remoteDetail"],
            "unknown": "未知（" + facts["remoteDetail"] + "）",
        }.get(facts["remote"], "未知")),
        "",
        "下一个检查点",
        "  名称: %s" % (facts["checkpoint"]["name"] or "未知"),
        "  条件: %s %s" % (facts["checkpoint"]["evidence"], facts["checkpoint"]["condition"]),
        "",
        "下一行动（不等于检查点）",
        "  %s %s" % (facts["nextAction"]["evidence"], facts["nextAction"]["detail"]),
        "  执行权限: 路线图只提供导航，不授予本地修改、tracker 写入或交付权限。",
        "",
        "完成边界",
        "  模块：任务完成证据、计划验证条件，以及适用的交付条件均需分别确认。",
        "  Initiative：活跃能力图中的模块均有明确终态，且无未解决依赖或证据断链。",
        "",
        "执行上下文",
        "  工作区目录: %s" % (git["root"] or "未知"),
        "  工作区类型: %s" % ({"primary": "primary checkout", "linked": "linked worktree（附加工作区）"}.get(git["kind"], "未知")),
        "  Git 位置: %s%s" % (git["position"], (" @ " + git["head"]) if git["head"] and "@" not in git["position"] else ""),
        "  未提交改动: %s" % git["dirty"],
        "  注: worktree 与分支只说明代码执行位置，不构成模块绑定或任务授权。",
    ]
    if all_modules:
        lines.extend(["", "活跃能力图模块（--all）"])
        for module in facts["modules"]:
            lines.append("  - %s（依赖: %s）" % (module["id"], _join(module["dependsOn"])))
    if facts["problems"]:
        lines.extend(["", "已知问题"] + facts["problems"])
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args(argv)
    facts = collect(args.project)
    print(render(facts, all_modules=args.all))
    return 0 if facts["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
