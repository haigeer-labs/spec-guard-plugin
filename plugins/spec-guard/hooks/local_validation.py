"""Read-only local-validation context; never grants task authority."""
import json
from pathlib import Path
import sys

from capability_map import MODULE_ID, parse_map


def inspect_stage(project):
    root = Path(project)
    path = root / ".agent/state.json"
    if not path.exists():
        return "absent", ""
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "invalid", "state.json 无法读取或解析"
    return validate_state(root, state)


def validate_state(root, state):
    root = Path(root)
    if not isinstance(state, dict):
        return "invalid", "state.json 必须是对象"
    if "workflowStage" not in state:
        return "absent", ""
    if state["workflowStage"] != "local-validation":
        return "invalid", "workflowStage 仅支持 local-validation 或省略字段"
    if state.get("tracker") not in ("github", "gitlab"):
        return "invalid", "本地验证需明确声明 github/gitlab tracker"
    if not isinstance(state.get("issueTypes"), bool):
        return "invalid", "issueTypes 必须是布尔值"
    initiative = state.get("initiative")
    if not isinstance(initiative, dict):
        return "invalid", "initiative 必须是对象"
    title = initiative.get("title")
    if not isinstance(title, str) or not title.strip():
        return "invalid", "initiative.title 不能为空"
    if "issue" not in initiative or initiative["issue"] is not None or state.get("modules") != {}:
        return "invalid", "本地验证要求 initiative.issue=null 且 modules 为空对象"
    if initiative.get("map") != "spec/CAPABILITY-MAP.md":
        return "invalid", "initiative.map 必须指向 spec/CAPABILITY-MAP.md"
    module = state.get("activeModule")
    if not isinstance(module, str) or not MODULE_ID.fullmatch(module):
        return "invalid", "activeModule 必须是单一合法模块 ID"
    try:
        parsed = parse_map(root / initiative["map"])
    except (OSError, ValueError):
        return "invalid", "能力图缺失或结构不合法"
    if module not in parsed.order:
        return "invalid", "activeModule 不属于当前能力图"
    for artifact in ("spec/%s.md" % module, "tasks/%s/plan.md" % module):
        if not (root / artifact).is_file():
            return "invalid", "当前模块缺少 spec 或 plan"
    return "valid", "tracker 尚未激活；本地上下文不代表任务领取或执行授权"


if __name__ == "__main__":
    status, message = inspect_stage(sys.argv[1] if len(sys.argv) > 1 else ".")
    print(status + "|" + message)
