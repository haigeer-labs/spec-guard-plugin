#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# setup-convention.sh —— 在当前项目落地目录约定（确定性执行）
#
# /setup-convention 命令调用本脚本，而不是让 LLM 逐步解释执行。
# 理由：写文件是幂等性和安全性要求高的操作，不能有非确定性。
#
# 用法:
#   bash setup-convention.sh github [--dry-run]
#   bash setup-convention.sh local  [--dry-run]
# ─────────────────────────────────────────────────────────────
set -uo pipefail

MODE="${1:-github}"
DRY=false
for a in "$@"; do [ "$a" = "--dry-run" ] && DRY=true; done
case "$MODE" in github|local) ;; *) echo "模式必须是 github 或 local"; exit 2 ;; esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="${CLAUDE_PLUGIN_ROOT:-$(dirname "$HERE")}/templates"
[ -d "$TPL" ] || TPL="$(dirname "$HERE")/templates"
[ -d "$TPL" ] || { echo "❌ 找不到 templates 目录（试过 ${TPL}）"; exit 1; }

MARK_B="<!-- BEGIN:agent-skills-convention -->"
MARK_E="<!-- END:agent-skills-convention -->"
F=0
act(){ [ "$DRY" = true ] && printf '  [dry-run] %s\n' "$1" || printf '  ✅ %s\n' "$1"; }
skip(){ printf '  ⏭  %s\n' "$1"; }
bad(){ printf '  ❌ %s\n' "$1"; F=1; }

echo "═══ 前置检查 ═══"
command -v python3 >/dev/null 2>&1 && echo "  ✅ python3" || bad "python3 缺失（hook 依赖）"
git rev-parse --git-dir >/dev/null 2>&1 && echo "  ✅ git 仓库" || bad "不在 git 仓库内，先 git init"

if [ "$MODE" = "github" ]; then
  if command -v gh >/dev/null 2>&1; then
    V=$(gh --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    MAJ=${V%%.*}; R=${V#*.}; MIN=${R%%.*}
    if [ "${MAJ:-0}" -gt 2 ] || { [ "${MAJ:-0}" -eq 2 ] && [ "${MIN:-0}" -ge 94 ]; }; then
      echo "  ✅ gh $V"
    else
      bad "gh $V < 2.94.0（缺 --type/--parent/--blocked-by），升级或改用 local 模式"
    fi
    # 版本号可能来自 PATH 里另一个 gh，验证参数真实存在
    # 不能用管道：grep -q 命中即关管道，gh 吃 SIGPIPE(141)，pipefail 传出
    # → 实测 30 次里 12 次假阻塞。herestring 无管道，30/30 稳定。
    if grep -q -- "--parent" <<<"$(gh issue create --help 2>/dev/null)"; then
      echo "  ✅ gh issue create 支持 --parent"
    else
      bad "gh issue create 无 --parent —— 跑 'type -a gh' 检查 PATH 里是否有多个 gh"
    fi
    gh auth status >/dev/null 2>&1 && echo "  ✅ gh 已认证" || echo "  ⚠️  gh 未认证（gh auth login）"
  else
    bad "未安装 gh（github 模式必需，或改用 local）"
  fi
  RM=$(git remote get-url origin 2>/dev/null || echo "")
  case "$RM" in
    *github*) echo "  ✅ 远端是 GitHub" ;;
    "")       echo "  ⚠️  无 origin 远端" ;;
    *)        echo "  ⚠️  远端非 GitHub（${RM}），建议 local 模式" ;;
  esac

  # issue types 是**组织级**功能：个人仓库上 `--type Feature/Task` 直接失败。
  # 光查 gh 版本和参数存在性不够 —— 那两项在个人仓库上一样全绿，
  # 然后 /sync-map 的第一条命令就炸。所以这里问一次仓库本身。
  # 探测不到就降级为警告，绝不假阻塞。
  case "$RM" in
    *github*)
      NWO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")
      if [ -z "$NWO" ]; then
        echo "  ⚠️  读不到仓库信息，跳过 issue types 探测（不代表可用）"
      else
        Q='query($o:String!,$n:String!){repository(owner:$o,name:$n){issueTypes(first:1){nodes{name}}}}'
        IT=$(gh api graphql -f query="$Q" -F o="${NWO%%/*}" -F n="${NWO#*/}" 2>/dev/null \
             | python3 -c "
import json,sys
try:
    r=json.load(sys.stdin)['data']['repository']['issueTypes']
    print('none' if r is None else 'ok')
except Exception:
    print('unknown')" 2>/dev/null)
        case "${IT:-unknown}" in
          ok)   echo "  ✅ $NWO 支持 issue types" ;;
          none) bad "$NWO 不支持 issue types —— 这是组织级功能，个人仓库用不了。
       改用 local 模式，或把仓库放到组织下并在组织设置里启用 issue types。
       不要退化用 label 模拟：label 无层级无依赖，/build 的筛选逻辑会全废。" ;;
          *)    echo "  ⚠️  issue types 探测失败，跳过（不代表可用）" ;;
        esac
      fi
      ;;
  esac
fi

[ "$F" -eq 0 ] || { echo ""; echo "存在阻塞项，未做任何改动。"; exit 1; }

echo ""
echo "═══ 落地约定（模式：${MODE}）═══"

# 已安装则只报告
if [ -f CLAUDE.md ] && grep -q "$MARK_B" CLAUDE.md 2>/dev/null; then
  skip "CLAUDE.md 声明块已存在（如需换模式，手动替换标记之间的内容）"
  ALREADY=true
else
  ALREADY=false
fi

if [ "$DRY" = false ]; then mkdir -p spec tasks .agent; fi
act "目录 spec/ tasks/ .agent/"

# CLAUDE.md：追加，绝不覆盖
if [ "$ALREADY" = false ]; then
  SRC="$TPL/claude-block-$( [ "$MODE" = github ] && echo github || echo local ).md"
  [ -f "$SRC" ] || bad "模板缺失: $SRC"
  if [ "$DRY" = false ] && [ -f "$SRC" ]; then
    [ -f CLAUDE.md ] && printf '\n' >> CLAUDE.md
    { echo "$MARK_B"; cat "$SRC"; echo "$MARK_E"; } >> CLAUDE.md
  fi
  act "CLAUDE.md 声明块（追加）"
fi

# state.json：不覆盖
if [ -f .agent/state.json ]; then
  skip ".agent/state.json 已存在"
else
  T=$( [ "$MODE" = github ] && echo github || echo none )
  if [ "$DRY" = false ]; then
    cat > .agent/state.json <<EOF
{
  "tracker": "$T",
  "initiative": { "title": "", "issue": null, "map": "spec/CAPABILITY-MAP.md" },
  "modules": {},
  "activeModule": "",
  "updatedAt": ""
}
EOF
  fi
  act ".agent/state.json (tracker=$T)"
fi

# 能力图：不覆盖
if [ -f spec/CAPABILITY-MAP.md ]; then
  skip "spec/CAPABILITY-MAP.md 已存在"
else
  [ "$DRY" = false ] && cp "$TPL/CAPABILITY-MAP.md" spec/CAPABILITY-MAP.md
  act "spec/CAPABILITY-MAP.md（模板）"
fi

[ "$DRY" = true ] && { echo ""; echo "（dry-run，未写入任何文件）"; exit 0; }

echo ""
echo "═══ 自检 ═══"
HOOK="${CLAUDE_PLUGIN_ROOT:-$(dirname "$HERE")}/hooks/phase-guard.sh"
[ -f "$HOOK" ] || HOOK="$HERE/phase-guard.sh"
if [ -f "$HOOK" ]; then
  OUT=$(CLAUDE_PROJECT_DIR="$(pwd)" bash "$HOOK" 2>/dev/null)
  if grep -q hookSpecificOutput <<<"${OUT}"; then
    P=$(printf '%s' "$OUT" | python3 -c "
import sys,json,re
c=json.load(sys.stdin)['hookSpecificOutput']['additionalContext']
print(re.search(r'当前阶段: \*\*(.+?)\*\*',c).group(1))" 2>/dev/null)
    echo "  ✅ hook 正常，当前阶段：$P"
  else
    bad "hook 无输出 —— 检查 CLAUDE.md 是否含约定标题"
  fi
else
  echo "  ⚠️  找不到 hook（${HOOK}），跳过自检"
fi

echo ""
echo "═══ 完成 ═══"
echo ""
echo "⚠️  下列文件要提交进仓库，队友才能共享同一套约定："
git status --short CLAUDE.md spec/ .agent/ 2>/dev/null | sed 's/^/     /'
echo ""
echo "下一步："
echo "  1. 编辑 spec/CAPABILITY-MAP.md 填入模块划分"
echo "  2. 人工评审模块边界和 build order（不能跳）"
if [ "$MODE" = github ]; then
  echo "  3. /sync-map   把能力图落成 GitHub Issue"
  echo "  4. /planning   为第一个模块拆解任务"
else
  echo "  3. /spec       为第一个模块生成 spec/<module-id>.md"
  echo "  4. /planning   拆解任务到 tasks/<module-id>/todo.md"
fi
