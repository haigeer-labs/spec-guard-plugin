#!/usr/bin/env bash
# Codex 插件真实宿主 smoke。--selftest 只验证判决器，绝不调用 Codex。
# 退出码：0=hook 已执行且输出有效；1=行为失败；2=环境未就绪。
set -uo pipefail

MODE=run
PLUGIN_ID=""
EXPECTED_SOURCE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --selftest) MODE=--selftest; shift ;;
    --plugin-id)
      [ "$#" -ge 2 ] || { echo '缺少 --plugin-id 的值' >&2; exit 2; }
      PLUGIN_ID="$2"; shift 2
      ;;
    --expected-source)
      [ "$#" -ge 2 ] || { echo '缺少 --expected-source 的值' >&2; exit 2; }
      EXPECTED_SOURCE="$2"; shift 2
      ;;
    *) echo "用法: $0 [--selftest] [--plugin-id <id> --expected-source <plugin-dir>]" >&2; exit 2 ;;
  esac
done

plugin_state() { # $1=插件清单 $2=目标插件 ID（可选）$3=候选插件目录（可选）
  python3 - "$1" "${2:-}" "${3:-}" <<'PY'
import json
import os
import sys

try:
    with open(sys.argv[1]) as f:
        plugins = json.load(f).get("installed", [])
except (OSError, ValueError, TypeError):
    print("unknown")
    raise SystemExit

plugin_id, expected_source = sys.argv[2:]
candidates = [
    plugin for plugin in plugins
    if plugin.get("name") == "spec-guard" and plugin.get("installed") is True
]
if plugin_id:
    candidates = [plugin for plugin in candidates if plugin.get("pluginId") == plugin_id]
if not candidates:
    print("missing")
    raise SystemExit
enabled = [plugin for plugin in candidates if plugin.get("enabled") is True]
if not enabled:
    print("disabled")
    raise SystemExit
if len(enabled) != 1:
    print("ambiguous")
    raise SystemExit
plugin = enabled[0]
if expected_source:
    installed_source = (plugin.get("source") or {}).get("path")
    if not isinstance(installed_source, str) or os.path.realpath(installed_source) != os.path.realpath(expected_source):
        print("source-mismatch")
        raise SystemExit
print("ready")
PY
}

print_plugin_repair() {
  echo "     codex plugin marketplace add /path/to/spec-guard-plugin"
  echo "     codex plugin add spec-guard@spec-guard-marketplace"
}

grade() { # $1=transcript 或明确 hook 记录
  local record="$1"
  if [ ! -s "$record" ]; then
    echo "  ⏭  没有 transcript/hook 输出：环境未就绪"
    return 2
  fi
  if grep -q 'HOOK_UNTRUSTED\|HOOK_NOT_RUN' "$record"; then
    echo "  ⏭  hook 未信任或未执行：在新会话用 /hooks 审核并信任"
    return 2
  fi
  if grep -q '当前阶段:' "$record"; then
    echo "  ✅ 收到 spec-guard hook 注入的当前阶段"
    return 0
  fi
  if grep -q 'HOOK_EXECUTED' "$record"; then
    echo "  ❌ hook 已执行，但输出未包含有效的当前阶段事实"
    return 1
  fi
  echo "  ⏭  无法证明 hook 是否执行：不把空输出判为产品失败"
  return 2
}

selftest() {
  local rc
  SMOKE_TMP="$(mktemp -d)"; trap 'rm -rf "$SMOKE_TMP"' EXIT
  printf '%s\n' 'HOOK_EXECUTED 当前阶段: PLANNED' > "$SMOKE_TMP/valid"
  grade "$SMOKE_TMP/valid"; rc=$?
  [ "$rc" -eq 0 ] || return 1
  printf '%s\n' 'HOOK_NOT_RUN' > "$SMOKE_TMP/untrusted"
  grade "$SMOKE_TMP/untrusted"; rc=$?
  [ "$rc" -eq 2 ] || return 1
  printf '%s\n' '{"installed":[]}' > "$SMOKE_TMP/missing-plugin.json"
  [ "$(plugin_state "$SMOKE_TMP/missing-plugin.json")" = missing ] || return 1
  printf '%s\n' '{"installed":[{"name":"spec-guard","installed":true,"enabled":false}]}' > "$SMOKE_TMP/disabled-plugin.json"
  [ "$(plugin_state "$SMOKE_TMP/disabled-plugin.json")" = disabled ] || return 1
  printf '%s\n' '{"installed":[{"name":"spec-guard","installed":true,"enabled":true}]}' > "$SMOKE_TMP/ready-plugin.json"
  [ "$(plugin_state "$SMOKE_TMP/ready-plugin.json")" = ready ] || return 1
  printf '%s\n' '{"installed":[{"pluginId":"spec-guard@stable","name":"spec-guard","installed":true,"enabled":true,"source":{"path":"/tmp/stable"}},{"pluginId":"spec-guard@candidate","name":"spec-guard","installed":true,"enabled":true,"source":{"path":"/tmp/candidate"}}]}' > "$SMOKE_TMP/ambiguous-plugin.json"
  [ "$(plugin_state "$SMOKE_TMP/ambiguous-plugin.json")" = ambiguous ] || return 1
  [ "$(plugin_state "$SMOKE_TMP/ambiguous-plugin.json" spec-guard@candidate /tmp/candidate)" = ready ] || return 1
  [ "$(plugin_state "$SMOKE_TMP/ambiguous-plugin.json" spec-guard@candidate /tmp/other)" = source-mismatch ] || return 1
  printf '%s\n' 'HOOK_EXECUTED {not-json}' > "$SMOKE_TMP/invalid"
  grade "$SMOKE_TMP/invalid"; rc=$?
  [ "$rc" -eq 1 ] || return 1
  echo "  ✅ selftest: 0=通过、1=行为失败、2=环境未就绪"
}

[ "$MODE" = "--selftest" ] && { selftest; exit $?; }
if { [ -n "$PLUGIN_ID" ] && [ -z "$EXPECTED_SOURCE" ]; } \
  || { [ -z "$PLUGIN_ID" ] && [ -n "$EXPECTED_SOURCE" ]; }; then
  echo '--plugin-id 与 --expected-source 必须同时指定' >&2
  exit 2
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "  ⏭  找不到 codex：先安装 Codex CLI，再从本地 marketplace 安装 spec-guard"
  print_plugin_repair
  exit 2
fi

PLUGIN_LIST="$(mktemp)"
trap 'rm -f "$PLUGIN_LIST"' EXIT
if ! codex plugin list --available --json > "$PLUGIN_LIST" 2>/dev/null; then
  echo "  ⏭  无法读取 Codex 插件清单：先登录后重试"
  exit 2
fi
case "$(plugin_state "$PLUGIN_LIST" "$PLUGIN_ID" "$EXPECTED_SOURCE")" in
  ready) ;;
  missing)
    echo "  ⏭  spec-guard 未从本地 marketplace 安装：先安装并启用插件"
    print_plugin_repair
    exit 2
    ;;
  disabled)
    echo "  ⏭  spec-guard 未启用：重新添加插件以启用"
    print_plugin_repair
    exit 2
    ;;
  ambiguous)
    echo "  ⏭  检测到多个已启用的 spec-guard：用 --plugin-id 与 --expected-source 指定本次候选"
    exit 2
    ;;
  source-mismatch)
    echo "  ⏭  已安装 spec-guard 的来源不是当前候选：先从该候选安装，再运行 smoke"
    exit 2
    ;;
  *)
    echo "  ⏭  无法判定 spec-guard 的安装状态：检查 codex plugin list --available --json"
    exit 2
    ;;
esac

WORK="$(mktemp -d)"
trap 'rm -f "$PLUGIN_LIST"; rm -rf "$WORK"' EXIT
( cd "$WORK" && git init -q && git config user.email smoke@example.invalid && git config user.name smoke )
printf '%s\n' '<!-- BEGIN:spec-guard-codex-convention -->' > "$WORK/AGENTS.md"
printf '%s\n' '<!-- END:spec-guard-codex-convention -->' >> "$WORK/AGENTS.md"
OUT="$WORK/transcript" ERR="$WORK/transcript.err"
PROMPT='请只复述你收到的 spec-guard 当前阶段事实；若没有收到，输出 HOOK_NOT_RUN。'
if ! ( cd "$WORK" && codex exec "$PROMPT" ) > "$OUT" 2> "$ERR"; then
  if grep -qi 'trust\|untrusted\|login\|auth' "$ERR"; then
    echo "  ⏭  Codex、登录或 hook trust 未就绪；用 /hooks 审核并信任后重试"
  else
    echo "  ⏭  Codex 非交互执行失败；这次 smoke 没跑起来，不是产品结论"
    sed -n '1,5p' "$ERR" | sed 's/^/     /'
  fi
  exit 2
fi
grade "$OUT"
