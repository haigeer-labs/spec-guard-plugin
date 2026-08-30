#!/usr/bin/env bash
# Codex 插件清单与 hook 适配器回归测试
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGDIR="$(cd "$HOOKDIR/.." && pwd)"
MANIFEST="$PLUGDIR/.codex-plugin/plugin.json"
CLAUDE_MANIFEST="$PLUGDIR/.claude-plugin/plugin.json"
HOOKS="$HOOKDIR/hooks.json"
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
if manifest.get("description") != "多模块 Spec 目录约定、GitHub Issue 打通与链路检测。":
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
