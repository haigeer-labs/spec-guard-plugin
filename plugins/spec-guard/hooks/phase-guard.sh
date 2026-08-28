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
  # 两条编码路径:jq 优先,python3 兜底。任一失败都往下一条走。
  out=""
  if command -v jq >/dev/null 2>&1; then
    out=$(jq -cn --arg c "$1" \
      '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}' 2>/dev/null)
  fi
  if [ -z "$out" ] && command -v python3 >/dev/null 2>&1; then
    out=$(printf '%s' "$1" | python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                         "additionalContext": sys.stdin.read()}}))' 2>/dev/null)
  fi
  # 两条都失败就**什么都不输出**。原先是无条件 printf 拼 JSON,
  # python3 一失败命令替换就是空,吐出 {"...":} —— 半截 JSON。
  # 宿主会拒绝整个 hook,而拒绝同样是静默的:一样坏,但更难查。
  # 宁可静默,也不要形如 JSON 的垃圾。
  [ -n "$out" ] && printf '%s\n' "$out"
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
#   两种激活信号，满足其一即可：
#     1. CLAUDE.md 里的约定标题（常规模式）
#     2. .agent/state.json 存在（**零 CLAUDE.md 足迹模式**）
#   加第 2 条是为了让不想动 CLAUDE.md 的项目也能用：那个文件官方建议
#   控制在 200 行内，而声明块曾经一口气占掉 100 多行。
#   .agent/ 是本插件自己的目录，拿它当信号不会污染无关项目。
HAS_BLOCK=false
[ -f "CLAUDE.md" ] && grep -q "Agent Skills 集成约定" CLAUDE.md 2>/dev/null && HAS_BLOCK=true
ACTIVE="$HAS_BLOCK"
[ -f ".agent/state.json" ] && ACTIVE=true
[ "$ACTIVE" = true ] || exit 0

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
  # herestring 而非管道：`head | grep -q` 里 grep 命中即关管道，还在写的 head
  # 吃到 SIGPIPE(141)，pipefail 把它传出来 —— 归档豁免失效，报出假违规。
  # 实测门槛是前 10 行约 256KB（真实 todo.md 到不了），但这是本仓明令禁止
  # 的写法，且同一条规则已经修过三次了。
  grep -qiE '已归档|ARCHIVED' <<<"$(head -10 "$1" 2>/dev/null)"
}

# 列出所有**非归档**的 todo.md
live_todos() {
  find tasks -name "todo.md" 2>/dev/null | while IFS= read -r t; do
    is_archived "$t" || printf '%s\n' "$t"
  done
}

# ── 自报版本 ───────────────────────────────────────────────
#   装出来的路径形如 .../spec-guard/0.7.2，末段就是版本号。
#   纯参数展开，**不 fork** —— 这个 hook 每轮都跑，预算 <1s。
#   加它的原因：更新插件要重启才生效，而「重启了没有 / 跑的是哪版」
#   之前只能靠翻 ~/.claude/plugins/cache 的 .in_use 标记猜。
SELF_DIR="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "${SELF_DIR}" ]; then
  SELF_DIR="${BASH_SOURCE[0]%/*}"; SELF_DIR="${SELF_DIR%/*}"
fi
PLUGIN_VER="${SELF_DIR##*/}"
case "${PLUGIN_VER}" in
  [0-9]*) PLUGIN_VER="v${PLUGIN_VER}" ;;
  *)      PLUGIN_VER="开发副本（未经 /plugin 安装）" ;;
esac

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
# 用 glob 而不是 `ls | grep`：后者拿**子串**排除，`spec/CAPABILITY-MAP-old.md`
# 这种也会被当成能力图剔掉。verify-artifacts 那边一直是整名相等
# （`grep -v "^CAPABILITY-MAP$"`），两边现在一致。
SPEC_COUNT=0
for f in spec/*.md; do
  [ -e "$f" ] || continue
  case "${f##*/}" in CAPABILITY-MAP.md) continue ;; esac
  SPEC_COUNT=$((SPEC_COUNT + 1))
done

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
  broken "存在 ${TODO_FOUND}，但本项目已声明外部 tracker —— 二者不能并存。若它是已完成模块的历史记录，在前 10 行内写上「已归档」即可豁免"
fi

# ── 4. GitHub 层 ───────────────────────────────────────────
OPEN_TASKS="?"; TOTAL_TASKS="?"; ASSIGNED=""; GH_OK=false
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
    # 总数（含已关闭）。**「全做完了」和「从没建过」在 OPEN_TASKS 上长得一模一样**，
    # 只有总数能把它们分开 —— 见下面 MODULE_DONE 前面那条分支。
    TOTAL_TASKS=$(printf '%s' "$RAW" | python3 -c "
import json,sys
try: print(len(json.load(sys.stdin)))
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
# 默认分支（模块 PR 的 base）。**不能只认 main/master 两个名字。**
# 默认分支叫 develop / trunk 的仓库上，本分支已落的 task 号一个都算不出来 ——
# 而 0.7.19 起「/next 跳过已做完的 task」这条筛选规则就靠这组号，
# 拿不到号 = 那个「刚做完的 task 被重新取一遍」的 bug 在这些仓库上原样存在。
#
# 顺序刻意先本地后远端、先 origin/HEAD 的名字后 main/master：
# 常见仓库（有本地 main）解析结果和 0.7.19 之前**逐字节相同**，只是把
# 覆盖面往外扩了一圈，不改已有行为。
# 全部落空就返回空 —— 调用方一律降级成「不排除任何东西」，
# 绝不反过来当成「都做完了」。
default_base() {
  local h n b
  h=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
  n="${h#origin/}"
  for b in "${n}" main master "$(git config --get init.defaultBranch 2>/dev/null || true)"; do
    [ -n "${b}" ] || continue
    git show-ref --verify --quiet "refs/heads/${b}" && { echo "${b}"; return; }
  done
  if [ -n "${h}" ] && git show-ref --verify --quiet "refs/remotes/${h}"; then echo "${h}"; return; fi
  for b in origin/main origin/master; do
    git show-ref --verify --quiet "refs/remotes/${b}" && { echo "${b}"; return; }
  done
  echo ""
}

# ── 模块级分支识别 ─────────────────────────────────────────
#   模块级 PR 约定下分支名是 <type>/<module-id>，**不含 issue 号**。
#   没有这一判定，下面「已认领但分支不含 issue 号」会把正常的模块分支报成
#   断链 —— 假断链比不报断链危害大得多。
#
#   **必须先判模块、判不中才去捡号**，不能反过来。
#   反过来的话 module id 自带数字（`feat/oauth2`）时，那个 `2` 会被当成
#   task issue 号，模块分支被降级成 task 分支，接着建议「/deliver 开 PR
#   （Closes #2）」—— 号是从分支名里捡的，跟这个模块毫无关系；而且它在
#   模块分支上劝你开 task PR，正是 0.6.0 要治的那件事。
#   verify-artifacts 0.7.11 修的就是这个，当时只修了那一边（见该文件顶部
#   「重叠项的判定规则必须两边一致」），phase-guard 到 0.7.12 才跟上。
ON_MODULE_BRANCH=false
if [ -n "${BRANCH}" ] && [ -n "${MODULE}" ]; then
  # 必须是**末段整段**相等，不是子串包含 —— 子串匹配下 module id 叫 "a"
  # 时分支 "master" 会被认成模块分支。
  case "${BRANCH}" in
    "${MODULE}"|*/"${MODULE}") ON_MODULE_BRANCH=true ;;
  esac
fi
# 带 issue 号的 task 分支（老约定）仍然支持，但模块分支优先。
BRANCH_ISSUE=""
[ "${ON_MODULE_BRANCH}" = false ] \
  && BRANCH_ISSUE=$(printf '%s' "$BRANCH" | grep -oE '[0-9]+' | head -1 || true)

# 本分支已经落了哪几个 task。模块级 PR 下 task issue 要到 PR 合并才关，
# OPEN_TASKS 全程不减 —— 「这个模块做完没有」只能从 commit message 的
# closing keyword 数。这只喂 NEXT 建议，**不进 broken()**：数偏了顶多建议早了。
#
# 要的是**号的集合**，不只是个数（0.7.19）。个数只够回答「做完没有」，
# 而 /next 要回答的是「下一个取哪条」—— 已经做完的那些在整个模块周期里
# 一直是 open，操作三的四条筛选规则一条都挡不住它们，于是刚做完的 task
# 被原样重新取出来做第二遍。号一直在手里，只是从来没往外露过。
TASKS_DONE_HERE=0
DONE_NUMS=""
if [ "${ON_MODULE_BRANCH}" = true ]; then
  BASE=$(default_base)
  if [ -n "${BASE}" ] && [ "${BASE}" != "${BRANCH}" ]; then
    DONE_NUMS=$(git log -n 200 --format=%B "${BASE}..HEAD" 2>/dev/null \
      | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#[0-9]+' \
      | grep -oE '[0-9]+' | sort -u || true)
    TASKS_DONE_HERE=$(printf '%s' "${DONE_NUMS}" | grep -c . || true)
    [ -z "${TASKS_DONE_HERE}" ] && TASKS_DONE_HERE=0
  fi
fi
# 取不到 BASE（既没有 main 也没有 master）时集合为空，表现为「这条规则不排除
# 任何东西」—— 不能反过来当成「全都做完了」，那会在非常规默认分支名的仓库上
# 一个 task 都取不出来，且看起来像模块已完成。
DONE_LIST=$(printf '%s' "${DONE_NUMS}" | sed 's/^/#/' | tr '\n' ' ')

# ── 状态机判定 ─────────────────────────────────────────────
if [ "$HAS_MAP" = false ] && [ "$SPEC_COUNT" -eq 0 ]; then
  PHASE="IDLE"
  NEXT="/spec —— 还没有任何规格"

elif [ "$HAS_MAP" = true ] && [ "$SPEC_COUNT" -eq 0 ]; then
  PHASE="MAP_ONLY"
  broken "能力图已存在但一份模块 spec 都没有 —— Phase 0 走完了但没递归"
  NEXT="/spec 按 build order 为第一个模块生成 spec"

elif [ "$TRACKER" = "other" ] && [ -z "$MODULE_ISSUE" ]; then
  PHASE="SPECED (非 GitHub tracker)"
  broken "远端不是 GitHub，但 state.json 未声明 tracker 类型 —— 无法判定任务托管在哪"
  NEXT="在 .agent/state.json 里显式声明 \"tracker\": \"none\"（本地 todo.md）或 \"gitlab\"/\"jira\" 等"

elif [ "$SPEC_COUNT" -gt 0 ] && [ -z "$MODULE" ] && [ -f "$STATE" ]; then
  # state.json 在、但 activeModule 是空的 —— 这是**刻意声明的空闲**，不是断链。
  # 项目在两个 initiative 之间(上一批全部交付、下一批还没起)本来就是这个样子。
  # 早期版本在这里报断链，对着一堆已交付的 spec 催「去建 issue」—— 假断链。
  #
  # **这一条必须排在所有 tracker 分支之前。** 0.7.12 之前它排在本地模式之后，
  # 于是 tracker=none 的项目根本够不到豁免，落进下面那条，报出
  # 「有 spec 但没有 tasks//plan.md」+「/plan 为 [] 拆解任务」——
  # 路径里那个双斜杠和空的 [] 就是 MODULE="" 漏出来的。
  # 而本地模式没有任何命令负责给**第一个**模块设 activeModule
  # （/sync-map 是 github 专属），所以这是本地模式跑完 /spec 的必经状态。
  PHASE="IDLE (无活跃模块)"
  NEXT="起新模块时把 activeModule 写进 .agent/state.json；或 /spec 开新的一轮"

elif [ -z "$MODULE" ]; then
  # 到这里：有 spec、activeModule 为空、且 state.json **不存在**
  # （存在的话上一条已经接住了）。这是真断链，但要说对断的是什么 ——
  # 不能再往下走，否则下面每条分支都会把空 MODULE 拼进路径里。
  PHASE="SPECED"
  broken "spec 已存在但没有 .agent/state.json —— 无从知道活跃模块是哪个"
  if [ "$TRACKER" = "github" ]; then
    NEXT="/sync-map 把能力图和模块落成 issue"
  else
    NEXT="跑 /setup-convention 建出 .agent/state.json，并把 activeModule 写进去"
  fi

elif [ "$TRACKER" = "none" ]; then
  # ── 本地模式：任务清单是 tasks/<module>/todo.md，不涉及任何 issue 系统 ──
  if [ "$HAS_PLAN" = false ]; then
    PHASE="SPECED (本地模式)"
    broken "有 spec 但没有 tasks/$MODULE/plan.md —— 链路在此断开"
    NEXT="/plan 为 [$MODULE] 拆解任务"
  elif [ "$HAS_TODO" = false ]; then
    PHASE="PLANNED (本地模式)"
    broken "有 plan.md 但没有 tasks/$MODULE/todo.md —— 链路在此断开"
    NEXT="/plan 补出任务清单"
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

elif [ "$TRACKER" != "github" ]; then
  # 显式声明的非 GitHub tracker（gitlab / jira / linear …）。
  # 本插件的任务层自动化只覆盖 github 和 none，这里只做到 plan 层 ——
  # 而关键是**不能给 GitHub 专属建议**。0.7.6 之前这里有两条都在发生：
  #   · 有条目号 → 落进 GH_OK=false 分支，报「gh 不可用，恢复 gh 后 /next」
  #     （gh 不是不可用，是跟这个项目无关，修好了也没用）
  #   · 无条目号 → 建议 /sync-map，而那个命令会去 gh 建 GitHub issue
  # 跟 0.7.6 的零足迹注入是同一个形状：tracker 盲。
  # 走到这里时 activeModule 必非空 —— 空的情况上一分支已经按「刻意空闲」接住了。
  if [ -z "$MODULE_ISSUE" ]; then
    PHASE="SPECED (${TRACKER})"
    broken "activeModule=[${MODULE}] 在 .agent/state.json 里没有对应的 ${TRACKER} 条目号 —— 链路在此断开"
    NEXT="在 ${TRACKER} 里为 [${MODULE}] 建条目，把号写进 .agent/state.json 的 modules.${MODULE}.issue"
  elif [ "$HAS_PLAN" = false ]; then
    PHASE="TRACKED (${TRACKER})"
    broken "模块 [${MODULE}] 有 spec 和条目，但没有 tasks/${MODULE}/plan.md —— 链路在此断开"
    NEXT="/plan 为 [${MODULE}] 拆解任务"
  elif [ "$DIRTY" -gt 0 ]; then
    PHASE="BUILDING (${TRACKER})"
    NEXT="/test 验证 → /review（有 ${DIRTY} 处未提交改动）"
  else
    PHASE="PLANNED (${TRACKER})"
    NEXT="在 ${TRACKER} 里认领下一个任务后 /build —— 本插件的任务层自动化只覆盖 github 和 none"
  fi

elif [ "$SPEC_COUNT" -gt 0 ] && [ -z "$MODULE_ISSUE" ]; then
  # activeModule 有值却没有对应 issue。真断链。
  # （「连 state.json 都没有」由上面那条单独接住，所以这里 MODULE 必非空。）
  PHASE="SPECED"
  broken "activeModule=[$MODULE] 但 .agent/state.json 里没有它的 issue —— 链路在此断开"
  NEXT="/sync-map 把能力图和模块落成 issue"

elif [ "$HAS_PLAN" = false ]; then
  PHASE="TRACKED"
  broken "模块 [$MODULE] 有 spec 和 issue，但没有 tasks/$MODULE/plan.md —— 链路在此断开"
  NEXT="/plan 为 [$MODULE] 拆解任务"

elif [ "$GH_OK" = false ]; then
  # gh 不可用（未安装 / 未登录 / 离线）：降级为纯本地判定，不报 GitHub 相关断链
  if [ "${ON_MODULE_BRANCH}" = true ] && [ "$DIRTY" -gt 0 ]; then
    PHASE="BUILDING (模块分支, gh 不可用)"
    NEXT="/test 验证 → 提交（message 带 Closes #<task-issue>），有 ${DIRTY} 处未提交改动"
  elif [ "${ON_MODULE_BRANCH}" = true ]; then
    PHASE="MODULE_BRANCH (gh 不可用，降级判定)"
    NEXT="恢复 gh 后 /next 继续取任务；本分支已落 ${TASKS_DONE_HERE} 个 task"
  elif [ -n "$BRANCH_ISSUE" ] && [ "$DIRTY" -gt 0 ]; then
    PHASE="BUILDING (gh 不可用，降级判定)"
    NEXT="/test 验证 → /deliver 开 PR（有 $DIRTY 处未提交改动）"
  elif [ -n "$BRANCH_ISSUE" ]; then
    PHASE="TASK_READY (gh 不可用，降级判定)"
    NEXT="/deliver 开 PR（Closes #${BRANCH_ISSUE}）"
  else
    PHASE="PLANNED (gh 不可用，降级判定)"
    NEXT="恢复 gh 后 /next；或手动指定要做的 issue"
  fi

elif [ "$OPEN_TASKS" = "0" ] && [ "$TOTAL_TASKS" = "0" ]; then
  # 一个 sub-issue 都没有 ≠ 任务都做完了。
  # 走到这里 HAS_PLAN 必为 true（上面 TRACKED 那条已经把没 plan 的接住了），
  # 所以这是「plan.md 写了任务，但没人把它们建成 issue」。
  #
  # 为什么会漏：skill 的四个操作里，**只有「操作二：任务落库」没有命令触发**
  # —— 操作一/三/四 分别由 /sync-map、/next、/deliver 点名，操作二没有。
  # 于是 /plan 跑完就没有下一步指路，而 phase-guard 此前把
  # OPEN_TASKS=0 一律当成 MODULE_DONE，反过来劝人「推进到下一个模块」——
  # **一个 task 都没做的模块被宣告完成。**
  PHASE="PLANNED (任务未落库)"
  broken "模块 [$MODULE] 有 tasks/$MODULE/plan.md，但 issue #$MODULE_ISSUE 下一个 sub-issue 都没有 —— 任务没落库，链路在此断开"
  NEXT="按 spec-github-bridge 的「操作二：任务落库」把 plan.md 里的任务建成 sub-issue（这个模块若确实不需要 task，在 plan.md 里写明）"

elif [ "$OPEN_TASKS" = "0" ]; then
  PHASE="MODULE_DONE"
  NEXT="/next 推进到下一个模块（[$MODULE] 已无未关闭任务）"

elif [ "${ON_MODULE_BRANCH}" = true ] && [ "$DIRTY" -gt 0 ]; then
  PHASE="BUILDING (模块分支)"
  NEXT="/test 验证 → 提交（commit message 带 Closes #<task-issue>），有 ${DIRTY} 处未提交改动"

elif [ "${ON_MODULE_BRANCH}" = true ] && [ "$OPEN_TASKS" != "?" ] \
     && [ "${TASKS_DONE_HERE}" -gt 0 ] && [ "${TASKS_DONE_HERE}" -ge "$OPEN_TASKS" ]; then
  PHASE="MODULE_READY"
  NEXT="/deliver 开模块 PR —— [${MODULE}] 的 ${OPEN_TASKS} 个未关闭 task 在本分支都有对应 commit"

elif [ "${ON_MODULE_BRANCH}" = true ]; then
  PHASE="TASK_READY (模块分支)"
  NEXT="/build auto 跑完模块剩下的 task（或 /next 逐条取）——**留在 [${BRANCH}] 上，不要每个 task 开 PR**（已落 ${TASKS_DONE_HERE}/${OPEN_TASKS}）"

elif [ -n "$ASSIGNED" ] && [ -z "$BRANCH_ISSUE" ]; then
  PHASE="TASK_CLAIMED"
  broken "已认领 $ASSIGNED 但当前分支 [$BRANCH] 不含 issue 号，也不属于模块 [${MODULE}] —— 可能在错误分支上工作"
  NEXT="切到模块分支 <type>/${MODULE} 后 /build"

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
[ "$OPEN_TASKS" != "?" ] && add "GitHub: $OPEN_TASKS 个未关闭 task（sub-issue 共 ${TOTAL_TASKS} 个）${ASSIGNED:+, 已认领 $ASSIGNED}"
[ -n "$BRANCH" ] && add "git: 分支=$BRANCH, 未提交=$DIRTY"
if [ "${ON_MODULE_BRANCH}" = true ]; then
  if [ "${TASKS_DONE_HERE}" -gt 0 ]; then
    add "模块分支: 本分支已落 ${TASKS_DONE_HERE} 个 task 的 commit（${DONE_LIST}）—— 这些 issue 要到 PR 合入默认分支才关，取下一个任务时必须跳过它们"
  else
    add "模块分支: 本分支还没有带 closing keyword 的 commit"
  fi
fi
add "spec-guard: ${PLUGIN_VER}"

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

# 零足迹模式（没有声明块，靠 state.json 激活）要把那句触发指令补回来。
#
# 实测依据：evals/skill-deferral.sh 的 B 组就是这个模式 —— hook 正常激活、
# 状态照常注入，**模型全程没加载 skill**，转头按自己的想法设计表结构去了。
# 原先文档写的「靠 hook 每轮兜底」是想当然：hook 注入的是**状态**，
# 而让 skill 被加载的是那句**指令**。少了它，--no-claude-md 就是个陷阱。
#
# 只有零足迹项目才付这几行的代价；写了声明块的项目一个字都不多。
#
# **要分 tracker。** spec-github-bridge 全篇是 gh issue / --blocked-by / 模块级 PR，
# 对 tracker=none 的本地模式项目毫无意义，指过去只会让它去建根本不存在的 issue。
# 0.7.5 第一版没分，本地模式项目照样被指向那个 skill —— 又一次
# 「在一个配置下验证、全局发货」。
if [ "$HAS_BLOCK" = false ]; then
  if [ "$TRACKER" = "github" ]; then
    OUT="${OUT}
**本项目没有 CLAUDE.md 声明块（零足迹模式）。**
动 spec、拆任务、取任务、交付之前，先加载 \`spec-github-bridge\` skill ——
目录约定、issue 落库、模块级 PR 与合并策略全在里面。跳过它必然写出双真相源。
"
  else
    OUT="${OUT}
**本项目没有 CLAUDE.md 声明块，而 tracker 是「${TRACKER}」。**
零足迹模式只对 github 模式成立：那边的细则在 \`spec-github-bridge\` skill 里，
按需加载即可。**本地模式没有对应的 skill，目录约定除了声明块无处可放。**
建议跑 \`/setup-convention local\` 把声明块写回去（13 行）。
"
  fi
fi

OUT="${OUT}
建议下一步: $NEXT

以上是仓库客观状态。若用户意图与之冲突，以用户为准，但要先指出冲突。"

emit "$OUT"
