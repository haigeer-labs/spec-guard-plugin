#!/usr/bin/env bash
# Codex 插件清单与 hook 适配器回归测试
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGDIR="$(cd "$HOOKDIR/.." && pwd)"
MANIFEST="$PLUGDIR/.codex-plugin/plugin.json"
CLAUDE_MANIFEST="$PLUGDIR/.claude-plugin/plugin.json"
HOOKS="$HOOKDIR/hooks.json"
OPS_SKILL="$PLUGDIR/skills/spec-guard-ops/SKILL.md"
BRIDGE_SKILL="$PLUGDIR/skills/spec-github-bridge/SKILL.md"
README="$PLUGDIR/../../README.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok() { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "═══ Codex 适配器回归测试 ═══"

check_manifest() {
  python3 - "$1" "$CLAUDE_MANIFEST" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
claude = json.load(open(sys.argv[2], encoding="utf-8"))
if manifest.get("name") != "spec-guard":
    raise SystemExit("name 必须精确为 spec-guard")
if manifest.get("version") != claude.get("version"):
    raise SystemExit("version 必须与 Claude manifest 一致")
if manifest.get("description") != "多模块 Spec 目录约定、GitHub / GitLab Issue 打通与链路检测。":
    raise SystemExit("description 必须精确为 Codex 适配器描述")
if manifest.get("skills") != "./skills/":
    raise SystemExit("skills 必须精确为 ./skills/")
if manifest.get("hooks") != "./hooks/hooks.json":
    raise SystemExit("hooks 必须精确为 ./hooks/hooks.json")
PY
}

if [ ! -f "$MANIFEST" ] || [ ! -f "$CLAUDE_MANIFEST" ]; then
  bad "Codex manifest 存在: $MANIFEST"
else
  if check_manifest "$MANIFEST"; then
    ok "Codex manifest 身份、版本、描述、skills/hooks 精确注册"
  else
    bad "Codex manifest 注册错误"
  fi
fi

for field in name version description skills hooks; do
  python3 - "$MANIFEST" "$TMP/wrong-$field.json" "$field" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
manifest[sys.argv[3]] = "wrong-value"
json.dump(manifest, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  if check_manifest "$TMP/wrong-$field.json" >/dev/null 2>&1; then
    bad "manifest $field 错误 fixture 必须被拒绝"
  else
    ok "manifest $field 错误 fixture 被拒绝"
  fi
done

COMMAND=""
if python3 - "$HOOKS" > "$TMP/command" <<'PY'
import json
import sys

hooks = json.load(open(sys.argv[1], encoding="utf-8")).get("hooks", {})
if set(hooks) != {"UserPromptSubmit"}:
    raise SystemExit("hook event 必须且只能是 UserPromptSubmit")
entries = hooks["UserPromptSubmit"]
if len(entries) != 1 or len(entries[0].get("hooks", [])) != 1:
    raise SystemExit("UserPromptSubmit 必须有一个 command hook")
hook = entries[0]["hooks"][0]
if hook.get("type") != "command":
    raise SystemExit("hook type 必须是 command")
command = hook.get("command", "")
needle = 'ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"'
if needle not in command:
    raise SystemExit("command 未以 PLUGIN_ROOT/CLAUDE_PLUGIN_ROOT 定义 ROOT")
if 'SCRIPT="${ROOT}/hooks/phase-guard.sh"' not in command:
    raise SystemExit("command 未从 ROOT 定位 phase-guard.sh")
print(command)
PY
then
  COMMAND="$(<"$TMP/command")"
  ok "hooks 只注册 UserPromptSubmit，并优先使用 PLUGIN_ROOT"
else
  bad "hooks 注册或命令路径错误"
fi

mkdir -p "$TMP/project"
printf '%s\n' '## Agent Skills 集成约定' > "$TMP/project/CLAUDE.md"

valid_phase_json() {
  python3 - "$1" <<'PY'
import json
import sys

output = json.load(open(sys.argv[1], encoding="utf-8"))
hook = output.get("hookSpecificOutput", {})
if hook.get("hookEventName") != "UserPromptSubmit":
    raise SystemExit("hook event 不正确")
if "当前阶段:" not in hook.get("additionalContext", ""):
    raise SystemExit("未注入当前阶段")
PY
}

run_hook() {
  env -i PATH="$PATH" "$1=$PLUGDIR" CLAUDE_PROJECT_DIR="$TMP/project" \
    /bin/bash -c "$COMMAND" > "$2" 2> "$TMP/error"
}

if [ -n "$COMMAND" ] && run_hook PLUGIN_ROOT "$TMP/codex-output" \
  && valid_phase_json "$TMP/codex-output"; then
  ok "仅设 PLUGIN_ROOT 与 CLAUDE_PROJECT_DIR 时 phase-guard 注入当前阶段 JSON"
else
  bad "仅设 PLUGIN_ROOT 与 CLAUDE_PROJECT_DIR 时 phase-guard 未注入当前阶段 JSON"
fi

if [ -n "$COMMAND" ] && run_hook CLAUDE_PLUGIN_ROOT "$TMP/claude-output" \
  && valid_phase_json "$TMP/claude-output"; then
  ok "仅设 CLAUDE_PLUGIN_ROOT 与 CLAUDE_PROJECT_DIR 时 phase-guard 注入当前阶段 JSON"
else
  bad "仅设 CLAUDE_PLUGIN_ROOT 与 CLAUDE_PROJECT_DIR 时 phase-guard 未注入当前阶段 JSON"
fi

check_skills() {
  python3 - "$OPS_SKILL" "$BRIDGE_SKILL" "$README" <<'PY'
import sys

ops = open(sys.argv[1], encoding="utf-8").read()
bridge = open(sys.argv[2], encoding="utf-8").read()
readme = open(sys.argv[3], encoding="utf-8").read()

for operation in ("setup", "phase", "verify", "verify-history", "audit-history", "correct-history", "history-migration", "parallel-readiness", "parallel-safety-gate", "parallel-subagent-preflight", "teardown", "lifecycle", "sync-map", "next", "deliver"):
    if ops.count(f"`{operation}`") != 1:
        raise SystemExit(f"操作 {operation} 必须恰好声明一次")

if 'codex plugin list --available --json' not in ops:
    raise SystemExit("操作 skill 未从 Codex 插件清单定位根目录")
if 'plugin.get("name") == "spec-guard"' not in ops:
    raise SystemExit("操作 skill 未精确选择 spec-guard 插件")
if 'PLUGIN_ROOT' in ops or 'CLAUDE_PLUGIN_ROOT' in ops:
    raise SystemExit("操作 skill 不得假定 hook 环境变量会传给 agent shell")
if '<<<"$CODEX_PLUGINS"' in ops:
    raise SystemExit("操作 skill 不得用 here-string，Codex 只读 sandbox 无法创建临时文件")
if 'printf' not in ops or '| python3 -c' not in ops:
    raise SystemExit("操作 skill 必须用管道把插件清单传给 Python")
if 'PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"' not in ops:
    raise SystemExit("操作 skill 未安全定位项目根目录")
if 'setup-convention.sh" github --host=codex' not in ops:
    raise SystemExit("setup 未显式使用 --host=codex")
if 'phase-guard.sh"' not in ops or 'verify-artifacts.sh"' not in ops:
    raise SystemExit("phase/verify 未调用共享只读检查脚本")
if 'parallel-readiness.py' not in ops:
    raise SystemExit("parallel-readiness 未调用共享分析脚本")
if '--refresh' not in ops or '用户确认' not in ops:
    raise SystemExit("parallel-readiness 未要求用户确认 --refresh")
if 'UserPromptSubmit' in ops:
    raise SystemExit("parallel-readiness 不得接入 UserPromptSubmit hook")
if 'parallel-safety-gate.py' not in ops or 'manual-parallel-eligible' not in ops:
    raise SystemExit("parallel-safety-gate 必须声明共享入口与保守分类")
preflight_start = ops.find("## `parallel-subagent-preflight`")
preflight_end = ops.find("\n## `", preflight_start + 1)
preflight = ops[preflight_start:preflight_end if preflight_end != -1 else None]
for token in ("用户明确确认", "spawn_agent", "只读", "父会话", "等待", "汇总", "parallel-safety-gate.py", "manual-parallel-eligible", "parallel-guidance"):
    if token not in preflight:
        raise SystemExit(f"parallel-subagent-preflight 缺少必要约束：{token}")
for forbidden in ("创建顶层任务", "自动创建 worktree", "并行写入代码"):
    if forbidden in preflight:
        raise SystemExit(f"parallel-subagent-preflight 不得承诺：{forbidden}")
if '确认' not in ops:
    raise SystemExit("teardown 未要求用户确认")
if 'initiative-lifecycle.sh' not in ops or 'lifecycle' not in ops:
    raise SystemExit("lifecycle 未调用共享入口")
if 'verify-history.sh' not in ops or 'capability-history.py" audit' not in ops or 'correct --confirm' not in ops or 'history-migration.py' not in ops:
    raise SystemExit("历史操作未调用共享入口")
for operation in ("sync-map", "next", "deliver"):
    if f"`{operation}`" not in ops or "spec-github-bridge" not in ops:
        raise SystemExit(f"{operation} 未委派给 spec-github-bridge")

for operation in ("parallel-execute", "parallel-integrate", "parallel-reclaim", "parallel-register-worker", "parallel-status"):
    if ops.count(f"## `{operation}`") != 1:
        raise SystemExit(f"操作 {operation} 必须有唯一入口")
for token in ("PARALLEL_WRITES_DISABLED", "--details --format json", "recordedState", "完成与可回收性未核验", "无任务绑定的 canonical next/deliver"):
    if token not in ops:
        raise SystemExit(f"缺少并行暂停与只读路由约束：{token}")
if "宿主可回收" in ops:
    raise SystemExit("不能把 host ownership 当成可回收证据")

if "find ~/.claude/plugins" in bridge:
    raise SystemExit("bridge 不得猜测 ~/.claude/plugins 中的 digest 路径")
if "spec-digest:" not in bridge:
    raise SystemExit("bridge 未要求 hook 注入 spec-digest 事实")
if "停止" not in bridge or "spec-guard 未加载" not in bridge:
    raise SystemExit("bridge 未在 digest 事实缺失时明确停止")
for token in ("parallel-subagent-preflight", "Codex 专用", "用户明确确认", "只读预检", "不等于隔离 worktree"):
    if token not in readme:
        raise SystemExit(f"README 缺少子智能体预检边界说明：{token}")
PY
}

if [ -f "$OPS_SKILL" ] && [ -f "$BRIDGE_SKILL" ] && [ -f "$README" ] && check_skills; then
  ok "Codex 显式操作 skill 与 bridge digest 依赖约束正确"
else
  bad "Codex 显式操作 skill 或 bridge digest 依赖约束错误"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
