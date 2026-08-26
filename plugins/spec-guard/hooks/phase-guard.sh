#!/bin/bash
# ─────────────────────────────────────────────────────────────
# phase-guard.sh —— agent-skills 链路守卫
#
# 挂在 UserPromptSubmit 上。每次用户发言前探测仓库真实状态，
# 把「当前处于哪个阶段 / 有没有断链」注入上下文。
#
# 设计原则：不做意图分类，只做状态注入。
#   意图分类靠 skill description 匹配，本来就不准；
#   状态是确定性的 —— 文件在不在、issue 有没有、分支干不干净。
#   模型看得见缺什么，路由自然就准了。
# ─────────────────────────────────────────────────────────────
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

emit() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg c "$1" \
      '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
      "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"
  fi
  exit 0
}

# ── tracker 模式判定 ───────────────────────────────────────
#   显式声明优先；否则按 git remote 推断；都没有则 none（本地 todo.md 模式）
detect_tracker() {
  local t
  t=$(jread "$STATE" "d.get('tracker')")
  [ -n "$t" ] && { echo "$t"; return; }
  local r; r=$(git remote get-url origin 2>/dev/null || echo "")
  case "$r" in
    *github.com*|*github.*) echo "github" ;;
    "")                     echo "none" ;;
    *)                      echo "other" ;;
  esac
}

# ── 只在启用了本约定的仓库生效 ──────────────────────────────
[ -f "CLAUDE.md" ] && grep -q "Agent Skills 集成约定" CLAUDE.md 2>/dev/null || exit 0

STATE=".agent/state.json"


# ── JSON 读取：优先 jq，缺失时用 python3 兜底 ──────────────
jread() {  # $1=file  $2=python 表达式(d 为根对象)
  [ -f "$1" ] || return 0
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    v=$2
    print(v if v is not None else '')
except Exception:
    print('')
" "$1" 2>/dev/null
  fi
}
# ── 归档识别 ──────────────────────────────────────────────
#   已完成的模块，其 todo.md 是**历史记录**，不是活的任务清单。
#   把它当成「与 tracker 并存」来报违规是误报 —— 而误报会让人关掉整个机制。
#   约定：文件**前 10 行**内出现 `已归档` 或 `ARCHIVED` 即视为归档。
#   放前 10 行是刻意的：只认头部声明，避免正文里偶然提到就被误判。
is_archived() {
  [ -f "$1" ] || return 1
  head -10 "$1" 2>/dev/null | grep -qiE '已归档|ARCHIVED'
}

# 列出所有**非归档**的 todo.md
live_todos() {
  find tasks -name "todo.md" 2>/dev/null | while IFS= read -r t; do
    is_archived "$t" || printf '%s\n' "$t"
  done
}

FACTS=""; BROKEN=""; NEXT=""

add()    { FACTS="${FACTS}  - $1"$'\n'; }
broken() { BROKEN="${BROKEN}  ⚠ $1"$'\n'; }

# ── 1. 活跃模块 ────────────────────────────────────────────
TRACKER=$(detect_tracker)
MODULE=""; MODULE_ISSUE=""
if [ -f "$STATE" ]; then
  MODULE=$(jread "$STATE" "d.get('activeModule')")
  [ -n "$MODULE" ] && MODULE_ISSUE=$(jread "$STATE" "d.get('modules',{}).get('$MODULE',{}).get('issue')")
fi

# ── 2. spec 层 ─────────────────────────────────────────────
HAS_MAP=false; SPEC_COUNT=0
[ -f "spec/CAPABILITY-MAP.md" ] && HAS_MAP=true
SPEC_COUNT=$(ls -1 spec/*.md 2>/dev/null | grep -v "CAPABILITY-MAP" | wc -l | tr -d ' ')

# 违规：spec 放错位置
if ls -1 SPEC*.md >/dev/null 2>&1; then
  broken "根目录有 SPEC*.md —— /build 的路径规则只认 spec/ 通配，挪进 spec/"
fi

# ── 3. plan 层 ─────────────────────────────────────────────
HAS_PLAN=false
[ -n "$MODULE" ] && [ -f "tasks/$MODULE/plan.md" ] && HAS_PLAN=true

# 违规：todo.md 和 tracker 并存
HAS_TODO=false
[ -n "$MODULE" ] && [ -f "tasks/$MODULE/todo.md" ] && HAS_TODO=true
TODO_FOUND=$(live_todos | head -1)
if [ "$TRACKER" != "none" ] && [ -n "$TODO_FOUND" ]; then
  broken "存在 ${TODO_FOUND}，但本项目已声明外部 tracker —— 二者不能并存"
fi

# ── 4. GitHub 层 ───────────────────────────────────────────
OPEN_TASKS="?"; ASSIGNED=""; GH_OK=false
if command -v gh >/dev/null 2>&1 && [ -n "$MODULE_ISSUE" ]; then
  # 必须用 REST sub_issues：`gh issue list` **没有** --parent 这个 flag
  # （--parent 只在 gh issue create 上）。早期版本用了它，结果每次都失败、
  # 静默落进「gh 不可用」降级分支 —— GitHub 层从来没真正跑过。
  RAW=$(gh api "repos/{owner}/{repo}/issues/${MODULE_ISSUE}/sub_issues" 2>/dev/null) || RAW=""
  if [ -n "$RAW" ]; then
    GH_OK=true
    # REST 返回所有状态，要自己筛 open
    OPEN_TASKS=$(printf '%s' "$RAW" | python3 -c "
import json,sys
try: print(len([i for i in json.load(sys.stdin) if i.get('state')=='open']))
except Exception: print('?')" 2>/dev/null)
    ASSIGNED=$(printf '%s' "$RAW" | python3 -c "
import json,sys
try:
    a=[i for i in json.load(sys.stdin) if i.get('state')=='open' and i.get('assignees')]
    print(f\"#{a[0]['number']} {a[0]['title']}\" if a else '')
except Exception: print('')" 2>/dev/null)
  fi
fi

# ── 5. git 层 ──────────────────────────────────────────────
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
DIRTY=$(git status --porcelain 2>/dev/null | grep -vE "^\?\? (spec/|tasks/|\.agent/)" | wc -l | tr -d " ")
[ -z "$DIRTY" ] && DIRTY=0
BRANCH_ISSUE=$(printf '%s' "$BRANCH" | grep -oE '[0-9]+' | head -1)

# ── 状态机判定 ─────────────────────────────────────────────
if [ "$HAS_MAP" = false ] && [ "$SPEC_COUNT" -eq 0 ]; then
  PHASE="IDLE"
  NEXT="/spec —— 还没有任何规格"

elif [ "$HAS_MAP" = true ] && [ "$SPEC_COUNT" -eq 0 ]; then
  PHASE="MAP_ONLY"
  broken "能力图已存在但一份模块 spec 都没有 —— Phase 0 走完了但没递归"
  NEXT="/spec 按 build order 为第一个模块生成 spec"

elif [ "$TRACKER" = "none" ]; then
  # ── 本地模式：任务清单是 tasks/<module>/todo.md，不涉及任何 issue 系统 ──
  if [ "$HAS_PLAN" = false ]; then
    PHASE="SPECED (本地模式)"
    broken "有 spec 但没有 tasks/$MODULE/plan.md —— 链路在此断开"
    NEXT="/planning 为 [$MODULE] 拆解任务"
  elif [ "$HAS_TODO" = false ]; then
    PHASE="PLANNED (本地模式)"
    broken "有 plan.md 但没有 tasks/$MODULE/todo.md —— 链路在此断开"
    NEXT="/planning 补出任务清单"
  elif [ -n "$BRANCH_ISSUE" ] && [ "$DIRTY" -gt 0 ]; then
    PHASE="BUILDING (本地模式)"
    NEXT="/test 验证 → /review"
  elif [ "$DIRTY" -gt 0 ]; then
    PHASE="BUILDING (本地模式)"
    NEXT="/test 验证 → /review（有 $DIRTY 处未提交改动）"
  else
    PHASE="READY (本地模式)"
    NEXT="/build 取 todo.md 里下一个未勾选任务"
  fi

elif [ "$TRACKER" = "other" ] && [ -z "$MODULE_ISSUE" ]; then
  PHASE="SPECED (非 GitHub tracker)"
  broken "远端不是 GitHub，但 state.json 未声明 tracker 类型 —— 无法判定任务托管在哪"
  NEXT="在 .agent/state.json 里显式声明 \"tracker\": \"none\"（本地 todo.md）或 \"gitlab\"/\"jira\" 等"

elif [ "$SPEC_COUNT" -gt 0 ] && [ -z "$MODULE" ] && [ -f "$STATE" ]; then
  # state.json 在、但 activeModule 是空的 —— 这是**刻意声明的空闲**，不是断链。
  # 项目在两个 initiative 之间(上一批全部交付、下一批还没起)本来就是这个样子。
  # 早期版本在这里报断链，对着一堆已交付的 spec 催「去建 issue」—— 假断链。
  PHASE="IDLE (无活跃模块)"
  NEXT="起新模块时把 activeModule 写进 .agent/state.json；或 /spec 开新的一轮"

elif [ "$SPEC_COUNT" -gt 0 ] && [ -z "$MODULE_ISSUE" ]; then
  # 到这里说明：要么 state.json 根本不存在，要么 activeModule 有值却没有对应 issue。
  # 两种都是真断链。
  PHASE="SPECED"
  if [ -n "$MODULE" ]; then
    broken "activeModule=[$MODULE] 但 .agent/state.json 里没有它的 issue —— 链路在此断开"
  else
    broken "spec 已存在但没有 .agent/state.json —— 链路在此断开"
  fi
  NEXT="/sync-map 把能力图和模块落成 issue"

elif [ "$HAS_PLAN" = false ]; then
  PHASE="TRACKED"
  broken "模块 [$MODULE] 有 spec 和 issue，但没有 tasks/$MODULE/plan.md —— 链路在此断开"
  NEXT="/planning 为 [$MODULE] 拆解任务"

elif [ "$GH_OK" = false ]; then
  # gh 不可用（未安装 / 未登录 / 离线）：降级为纯本地判定，不报 GitHub 相关断链
  if [ -n "$BRANCH_ISSUE" ] && [ "$DIRTY" -gt 0 ]; then
    PHASE="BUILDING (gh 不可用，降级判定)"
    NEXT="/test 验证 → /deliver 开 PR（有 $DIRTY 处未提交改动）"
  elif [ -n "$BRANCH_ISSUE" ]; then
    PHASE="TASK_READY (gh 不可用，降级判定)"
    NEXT="/deliver 开 PR（Closes #${BRANCH_ISSUE}）"
  else
    PHASE="PLANNED (gh 不可用，降级判定)"
    NEXT="恢复 gh 后 /next；或手动指定要做的 issue"
  fi

elif [ "$OPEN_TASKS" = "0" ]; then
  PHASE="MODULE_DONE"
  NEXT="/next 推进到下一个模块（[$MODULE] 已无未关闭任务）"

elif [ -n "$ASSIGNED" ] && [ -z "$BRANCH_ISSUE" ]; then
  PHASE="TASK_CLAIMED"
  broken "已认领 $ASSIGNED 但当前分支 [$BRANCH] 不含 issue 号 —— 可能在错误分支上工作"
  NEXT="切到 <type>/<issue>-<slug> 分支后 /build"

elif [ -n "$BRANCH_ISSUE" ] && [ "$DIRTY" -gt 0 ]; then
  PHASE="BUILDING"
  NEXT="/test 验证 → /deliver 开 PR（有 $DIRTY 处未提交改动）"

elif [ -n "$BRANCH_ISSUE" ] && [ "$DIRTY" -eq 0 ]; then
  PHASE="TASK_READY"
  NEXT="/deliver 开 PR（Closes #${BRANCH_ISSUE}）"

else
  PHASE="PLANNED"
  NEXT="/next 取下一个任务"
fi

# ── 组装事实 ───────────────────────────────────────────────
[ -n "$MODULE" ] && add "活跃模块: $MODULE${MODULE_ISSUE:+ (issue #$MODULE_ISSUE)}"
add "tracker: $TRACKER"
add "spec: 能力图=$HAS_MAP, 模块 spec=$SPEC_COUNT 份"
[ -n "$MODULE" ] && add "plan: tasks/$MODULE/plan.md=$HAS_PLAN"
[ "$OPEN_TASKS" != "?" ] && add "GitHub: $OPEN_TASKS 个未关闭 task${ASSIGNED:+, 已认领 $ASSIGNED}"
[ -n "$BRANCH" ] && add "git: 分支=$BRANCH, 未提交=$DIRTY"

OUT="## agent-skills 链路状态（自动探测，非用户输入）

当前阶段: **$PHASE**

$FACTS"

if [ -n "$BROKEN" ]; then
  OUT="${OUT}
**检测到断链：**
$BROKEN
处理方式：先向用户说明断链，给出补齐建议，**得到确认后再执行**。不要自作主张跳过或补齐。
"
fi

OUT="${OUT}
建议下一步: $NEXT

以上是仓库客观状态。若用户意图与之冲突，以用户为准，但要先指出冲突。"

emit "$OUT"
