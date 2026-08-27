#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# setup-convention.sh —— 在当前项目落地目录约定（确定性执行）
#
# /setup-convention 命令调用本脚本，而不是让 LLM 逐步解释执行。
# 理由：写文件是幂等性和安全性要求高的操作，不能有非确定性。
#
# 用法:
#   bash setup-convention.sh github [--dry-run] [--replace] [--no-claude-md]
#   bash setup-convention.sh local  [--dry-run] [--replace] [--no-claude-md]
#
#   --replace       已存在的声明块就地升级到当前模板（只动 BEGIN/END 之间）
#   --no-claude-md  完全不写声明块，hook 改由 .agent/state.json 激活
# ─────────────────────────────────────────────────────────────
set -uo pipefail

MODE="${1:-github}"
DRY=false
REPLACE=false      # 已存在的声明块：默认跳过，--replace 才就地升级
NO_BLOCK=false     # 零 CLAUDE.md 足迹：完全不写声明块，靠 .agent/state.json 激活
for a in "$@"; do
  case "$a" in
    --dry-run)      DRY=true ;;
    --replace)      REPLACE=true ;;
    --no-claude-md) NO_BLOCK=true ;;
  esac
done
case "$MODE" in github|local) ;; *) echo "模式必须是 github 或 local"; exit 2 ;; esac

# 零足迹模式靠 spec-github-bridge skill 承接细则，而本地模式**没有对应的 skill**。
# 去掉声明块之后目录约定无处可放 —— 装了等于没装，还比没装更迷惑
# （hook 会照常报状态，看着像在工作）。
if [ "$MODE" = local ] && [ "$NO_BLOCK" = true ]; then
  echo "❌ local 模式不支持 --no-claude-md。"
  echo "   零足迹模式是靠 spec-github-bridge skill 承接细则的，本地模式没有对应的 skill；"
  echo "   去掉声明块之后目录约定无处可放，装了等于没装。"
  echo "   → 要么用 github 模式，要么写声明块（本地模式的块只有 13 行）。"
  exit 2
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="${CLAUDE_PLUGIN_ROOT:-$(dirname "$HERE")}/templates"
[ -d "$TPL" ] || TPL="$(dirname "$HERE")/templates"
[ -d "$TPL" ] || { echo "❌ 找不到 templates 目录（试过 ${TPL}）"; exit 1; }

ISSUE_TYPES=unknown          # github 模式下由前置检查探测后覆盖
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
          ok)   ISSUE_TYPES=true;  echo "  ✅ $NWO 支持 issue types" ;;
          none) ISSUE_TYPES=false
                echo "  ⚠️  $NWO 不支持 issue types（组织级功能，个人仓库用不了）"
                echo "       → 自动降级：省略 --type，改用层级本身区分 task"
                echo "       → 层级(--parent)和依赖(--blocked-by)照常可用，实测已验证"
                echo "       → 不用 label 模拟 type：label 无层级无依赖，筛选逻辑会全废" ;;
          *)    ISSUE_TYPES=unknown; echo "  ⚠️  issue types 探测失败，按不可用处理（宁可少用一个参数）" ;;
        esac
      fi
      ;;
  esac
fi

[ "$F" -eq 0 ] || { echo ""; echo "存在阻塞项，未做任何改动。"; exit 1; }

echo ""
echo "═══ 落地约定（模式：${MODE}）═══"

# 已安装则只报告（--replace 时改为就地升级）
if [ -f CLAUDE.md ] && grep -q "$MARK_B" CLAUDE.md 2>/dev/null; then
  ALREADY=true
else
  ALREADY=false
fi

if [ "$DRY" = false ]; then mkdir -p spec tasks .agent; fi
act "目录 spec/ tasks/ .agent/"

# CLAUDE.md：追加，绝不覆盖标记之外的任何内容
SRC="$TPL/claude-block-$( [ "$MODE" = github ] && echo github || echo local ).md"
if [ "$NO_BLOCK" = true ]; then
  skip "CLAUDE.md 声明块（--no-claude-md）—— 改由 .agent/state.json 激活 hook"
elif [ "$ALREADY" = true ] && [ "$REPLACE" = false ]; then
  skip "CLAUDE.md 声明块已存在（升级到当前模板：加 --replace）"
elif [ "$ALREADY" = true ]; then
  # 就地替换标记之间的内容。**只动标记内**，标记外一个字节不碰。
  # 用 python3 而不是 sed：bash 3.2 的 sed 在多字节内容上不可靠。
  [ -f "$SRC" ] || bad "模板缺失: $SRC"
  if [ "$DRY" = false ] && [ -f "$SRC" ]; then
    OLDN=$(python3 - "$SRC" "$MARK_B" "$MARK_E" <<'PYEOF'
import sys
src, mb, me = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open('CLAUDE.md', encoding='utf-8').read().split('\n')
b = next(i for i, l in enumerate(lines) if l.strip() == mb)
e = len(lines) - 1 - next(i for i, l in enumerate(reversed(lines)) if l.strip() == me)
body = open(src, encoding='utf-8').read().rstrip('\n').split('\n')
out = lines[:b + 1] + body + lines[e:]
open('CLAUDE.md', 'w', encoding='utf-8').write('\n'.join(out))
print(e - b - 1)
PYEOF
) || OLDN="?"
    NEWN=$(wc -l < "$SRC" | tr -d ' ')
    act "CLAUDE.md 声明块（就地升级：${OLDN} 行 → ${NEWN} 行）"
  else
    act "CLAUDE.md 声明块（就地升级）"
  fi
else
  [ -f "$SRC" ] || bad "模板缺失: $SRC"
  if [ "$DRY" = false ] && [ -f "$SRC" ]; then
    [ -f CLAUDE.md ] && printf '\n' >> CLAUDE.md
    { echo "$MARK_B"; cat "$SRC"; echo "$MARK_E"; } >> CLAUDE.md
  fi
  act "CLAUDE.md 声明块（追加，$(wc -l < "$SRC" | tr -d ' ') 行）"
fi

# state.json：不覆盖
#
# teardown 会把它改名成 .disabled（保留 issue 编号映射）。这里必须认得出来 ——
# 否则「teardown 之后改主意再 setup」会静默建一个空的 state.json，
# 而真正的映射孤零零躺在 .disabled 里。后果不只是丢数据：模型会看到
# 「activeModule 没有 issue」→ 建议 /sync-map → **在 GitHub 上建出一套重复 issue**。
if [ -f .agent/state.json ]; then
  skip ".agent/state.json 已存在"
elif [ -f .agent/state.json.disabled ]; then
  OLDT=$(python3 -c "
import json,sys
try: print(json.load(open('.agent/state.json.disabled')).get('tracker') or '')
except Exception: print('')" 2>/dev/null)
  WANT=$( [ "$MODE" = github ] && echo github || echo none )
  if [ "${OLDT}" = "${WANT}" ]; then
    NMOD=$(python3 -c "
import json
try: print(len(json.load(open('.agent/state.json.disabled')).get('modules') or {}))
except Exception: print(0)" 2>/dev/null)
    [ "$DRY" = false ] && mv .agent/state.json.disabled .agent/state.json
    act "恢复 .agent/state.json（teardown 留下的 .disabled，${NMOD} 个模块的 issue 映射保留）"
  else
    bad "存在 .agent/state.json.disabled 但它的 tracker=[${OLDT:-空}] 与本次的 [${WANT}] 不符"
    printf '     不自动恢复也不新建 —— 新建会让 .disabled 里的 issue 映射被忘掉,\n'
    printf '     而下一步 /sync-map 会在 GitHub 上建出一套重复 issue。\n'
    # 不能写「用 <tracker> 模式重跑」—— 本脚本只收 github|local，
    # .disabled 里的 tracker 若是 gitlab/jira，那个建议根本做不到。
    case "${OLDT}" in
      github|none) printf '     二选一：用 %s 模式重跑；或先手工处理 .agent/state.json.disabled\n' \
                     "$( [ "${OLDT}" = github ] && echo github || echo local )" ;;
      *)           printf '     本脚本只收 github|local，而它是 [%s] —— 手工处理 .agent/state.json.disabled\n' \
                     "${OLDT:-空}" ;;
    esac
  fi
else
  T=$( [ "$MODE" = github ] && echo github || echo none )
  # issueTypes: true=可用（加 --type）  false=不可用（省略 --type，靠层级区分）
  ITJ=$( [ "$ISSUE_TYPES" = true ] && echo true || echo false )
  if [ "$DRY" = false ]; then
    cat > .agent/state.json <<EOF
{
  "tracker": "$T",
  "initiative": { "title": "", "issue": null, "map": "spec/CAPABILITY-MAP.md" },
  "issueTypes": ${ITJ},
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
if [ "$F" -ne 0 ]; then
  echo "═══ 未完成 ═══"
  echo "上面有 ❌ 的项没做，先处理它再重跑。"
  exit 1
fi
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
  echo "  4. /plan   为第一个模块拆解任务"
else
  echo "  3. /spec       为第一个模块生成 spec/<module-id>.md"
  echo "  4. /plan   拆解任务到 tasks/<module-id>/todo.md"
fi
