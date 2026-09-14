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

# 远端是不是 GitHub —— **只看 host 段**。
#   写 `*github.*` 会漏掉 SSH host 别名：`git@github-collab:o/r.git` 里
#   `github` 后面跟的是 `-` 不是 `.`，于是判成「远端不是 GitHub」，
#   而 state.json 还没建出来的项目会因此吃一条**假断链**（性质 2）。
#   实测出处：本插件作者自己的所有仓库都用 `github-collab:` 别名。
#   反过来也不能松成 `*github*` —— `gitlab.com/me/github-tools.git`
#   的路径里含 github，那是仓库名不是宿主。先剥到 host 再判。
remote_host() {  # $1=remote url
  local h="$1"
  h="${h#*://}"; h="${h#*@}"; h="${h%%/*}"; h="${h%%:*}"
  printf '%s\n' "$h"
}

is_github_remote() {  # $1=remote url
  local h
  h=$(remote_host "$1")
  case "$h" in *github*) return 0 ;; *) return 1 ;; esac
}

# GitLab.com 可从 host 无歧义判定；自建实例不能假定 host 含 gitlab（例如
# mgit.lgroup.co），更不能为了猜测 tracker 而在每次 hook 注入时访问 glab。
# 自建实例必须由 state.json 显式声明 tracker=gitlab；未声明则安全回退到 none。
is_gitlab_remote() {  # $1=remote url
  local h
  h=$(remote_host "$1")
  case "$h" in gitlab.com|*.gitlab.com) return 0 ;; esac
  return 1
}

# ── tracker 模式判定 ───────────────────────────────────────
#   显式声明优先；否则按 git remote 推断；不确定则 none（本地模式）。
detect_tracker() {
  local t
  t=$(jread "$STATE" "d.get('tracker')")
  [ -n "$t" ] && { echo "$t"; return; }
  local r; r=$(git remote get-url origin 2>/dev/null || echo "")
  if [ -z "$r" ]; then echo "none"
  elif is_github_remote "$r"; then echo "github"
  elif is_gitlab_remote "$r"; then echo "gitlab"
  else echo "none"; fi
}

# ── 只在启用了本约定的仓库生效 ──────────────────────────────
#   三种激活信号，满足其一即可：
#     1. CLAUDE.md 里的 Claude 约定标记或旧版约定标题（常规模式）
#     2. AGENTS.md 里的 Codex 完整约定标记（常规模式）
#     3. .agent/state.json 存在（零说明文件足迹模式）
#   加第 3 条是为了让不想动项目说明文件的项目也能用：那个文件官方建议
#   控制在 200 行内，而声明块曾经一口气占掉 100 多行。
#   .agent/ 是本插件自己的目录，拿它当信号不会污染无关项目。
has_claude_block() {
  if grep -q "<!-- BEGIN:agent-skills-convention -->" CLAUDE.md 2>/dev/null; then
    return 0
  fi
  grep -q "Agent Skills 集成约定" CLAUDE.md 2>/dev/null
}

has_codex_block() {
  grep -q "<!-- BEGIN:spec-guard-codex-convention -->" AGENTS.md 2>/dev/null
}

HAS_CLAUDE=false
has_claude_block && HAS_CLAUDE=true
HAS_CODEX=false
has_codex_block && HAS_CODEX=true
HAS_BLOCK=false
if [ "$HAS_CLAUDE" = true ] || [ "$HAS_CODEX" = true ]; then
  HAS_BLOCK=true
fi
ACTIVE="$HAS_BLOCK"
[ -f ".agent/state.json" ] && ACTIVE=true
IS_CODEX=false
[ -n "${PLUGIN_ROOT:-}" ] && IS_CODEX=true

# ── 休眠项目的唯一例外：已有多模块产物，却没落约定 ──────────
#   性质 1 说的是「不许污染无关项目」，不是「装了也不许被发现」。
#   代价面实测（delegate-plugin，0.7.28 之前）：新项目里直接 /spec，
#   agent-skills 把 SPEC-<mod>.md 和能力图散在根上、tasks/ 下建出
#   todo.md，**全程零提示**；等截图发现时已经三个模块九个文件，
#   只能手工迁移。README 问题①要治的正是这个形状，而插件在这里
#   恰恰是哑的。
#
#   判据必须挑「多模块」证据。根上孤零零一个 SPEC.md 是 agent-skills
#   完全合法的单模块形态，本插件对它没有价值 —— 报它就是性质 2 说的
#   假警报，而假警报比不报危害大得多。
#
#   只读、只建议、可静音（.spec-guard-ignore），不碰性质 3。
if [ "$ACTIVE" != true ]; then
  [ -f ".spec-guard-ignore" ] && exit 0

  STRAY=""
  for f in SPEC-*.md; do
    [ -e "$f" ] && { STRAY="根目录 ${f}"; break; }
  done
  if [ -z "$STRAY" ]; then
    # 大小写都认：macOS 默认大小写不敏感，但 Linux 上 capability-map.md
    # 和 CAPABILITY-MAP.md 是两个文件，写死一个必漏。
    for f in *.md; do
      case "$f" in
        [Cc][Aa][Pp][Aa][Bb][Ii][Ll][Ii][Tt][Yy]-[Mm][Aa][Pp].md)
          STRAY="根目录 ${f}"; break ;;
      esac
    done
  fi
  if [ -z "$STRAY" ]; then
    N=0
    for p in tasks/*/plan.md; do
      [ -e "$p" ] && N=$((N+1))
    done
    [ "$N" -ge 2 ] && STRAY="tasks/ 下 ${N} 个模块的 plan.md"
  fi
  [ -n "$STRAY" ] || exit 0

  # 建议哪个模式要按远端来。写死 github 的话，非 GitHub 项目照着跑会在
  # 前置检查（gh 版本 / --parent）上直接退 1 —— 把人指进一条走不通的路，
  # 比不提示更糟。
  if is_github_remote "$(git remote get-url origin 2>/dev/null || echo "")"; then
    SUGGEST_MODE=github
  else
    SUGGEST_MODE=local
  fi

  emit "## spec-guard：发现未落约定的多模块 spec 产物（自动探测，非用户输入）

${STRAY} —— 但本项目既没有 CLAUDE.md 声明块，也没有 .agent/state.json。
**spec-guard 的目录约定与链路检测在本项目上全程未生效**，\`/spec\` \`/plan\`
走的是 agent-skills 默认落点：多模块产物会散在根上或互相覆盖。

建议下一步: \`/spec-guard:setup-convention ${SUGGEST_MODE} --migrate --dry-run\` 先看会动哪些文件。
不打算在本项目用 spec-guard，就 \`touch .spec-guard-ignore\`，本提示即消失。"
fi

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
  awk 'NR > 10 { exit } tolower($0) ~ /已归档|archived/ { found=1 } END { exit !found }' "$1"
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
SELF_DIR="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
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
LOCAL_STAGE_RESULT=$(python3 "${SELF_DIR}/hooks/local_validation.py" "$ROOT" 2>/dev/null) \
  || LOCAL_STAGE_RESULT="invalid|本地阶段校验器不可用，不能确认上下文"
LOCAL_STAGE="${LOCAL_STAGE_RESULT%%|*}"
if [ "$LOCAL_STAGE" = absent ]; then
  TRACKER=$(detect_tracker)
else
  TRACKER=$(jread "$STATE" "d.get('tracker')")
fi
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

# 生命周期完成后，当前 map/state 会移入 history。老版本可能留下 module spec，
# 正常归档则什么 module spec 都不留；两种形状都必须读取同一份账本。只有账本本身
# 合法、至少有一条 initiative、且每条都处于终态时，才能判为已归档；不能因为
# 「看见 history 文件」就吞掉真正丢失 state 的断链。
HAS_ARCHIVED_HISTORY=false
LEDGER="spec/CAPABILITY-HISTORY.json"
if [ "$HAS_MAP" = false ] && [ ! -f "$STATE" ] \
   && [ -f "$LEDGER" ] && [ -f "${SELF_DIR}/hooks/capability-history.py" ] \
   && command -v python3 >/dev/null 2>&1 \
   && python3 "${SELF_DIR}/hooks/capability-history.py" validate "$LEDGER" >/dev/null 2>&1 \
   && python3 - "$LEDGER" >/dev/null 2>&1 <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    initiatives = json.load(handle).get("initiatives", [])
terminal = {"completed", "abandoned", "superseded"}
raise SystemExit(0 if initiatives and all(item["events"][-1]["type"] in terminal for item in initiatives) else 1)
PY
then
  HAS_ARCHIVED_HISTORY=true
fi

# 归档是本地文件操作；它本身不能证明外部 tracker 也已收口。
# lifecycle 保持离线：这里是 hook 中**可选、只读且显式 opt-in**的补充核验。
# 只有设置 SPEC_GUARD_ARCHIVE_REMOTE_VERIFY=1、归档账本最新事件为 completed，
# 且快照明确记录了外部 initiative 条目号（GitHub 还须记录 initiative.repository，
# 缺失时不回退到当前 origin），才查询。paused / abandoned /
# superseded 不等同于「远端必须关闭」，所以不作推断。
ARCHIVE_REMOTE_OPEN=""
ARCHIVE_REMOTE_UNVERIFIED=""
ARCHIVE_REMOTE_UNVERIFIABLE=""
ARCHIVE_SNAPSHOT_UNREADABLE=""
ARCHIVE_REMOTE_CLOSED=""
ARCHIVE_REMOTE_EXTERNAL=false
ARCHIVE_GITLAB_PROJECT_ID=""

archive_remote_verification_enabled() {
  [ "${SPEC_GUARD_ARCHIVE_REMOTE_VERIFY:-}" = "1" ]
}

# 归档快照的字段用 \x1f（非 IFS 空白）分隔，而不是 \t —— 缺失仓库身份时
# 该字段就是空字符串，tab 是 IFS 空白会在 read 时把相邻空字段折叠掉，
# 导致后面的仓库字段错位顶进 issue 变量。\x1f 不是空白，空字段原样保留。
archived_completed_trackers() {
  python3 - "$LEDGER" "$ROOT" <<'PY'
import json
import os
import re
import sys

FS = "\x1f"
CONTROL_CHARS = ("\n", "\r", "\x1f")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


def has_control_char(value):
    return any(ch in value for ch in CONTROL_CHARS)


def sanitize_id(value):
    for ch in CONTROL_CHARS:
        value = value.replace(ch, " ")
    return value


ledger_path, root = sys.argv[1:]
try:
    ledger = json.load(open(ledger_path, encoding="utf-8"))
except Exception:
    raise SystemExit
for initiative in ledger.get("initiatives", []):
    initiative_id = initiative.get("id", "unknown")
    if not isinstance(initiative_id, str):
        initiative_id = str(initiative_id)
    events = initiative.get("events", [])
    if not events or events[-1].get("type") != "completed":
        continue
    checkpoint = events[-1].get("checkpoint", {})
    # 早期账本没有状态快照：它不能告诉我们 tracker，保留旧的本地归档
    # 语义。新账本声明了 state 路径却读不到时，才是需要显式待核验的损坏。
    if "state" not in checkpoint:
        continue
    state = checkpoint.get("state") or {}
    state_path = state.get("path")
    if not isinstance(state_path, str) or not state_path.startswith(".agent/history/"):
        print(FS.join((initiative_id, "__snapshot_unreadable__", "", "")))
        continue
    absolute = os.path.abspath(os.path.join(root, state_path))
    if os.path.commonpath((os.path.abspath(root), absolute)) != os.path.abspath(root):
        print(FS.join((initiative_id, "__snapshot_unreadable__", "", "")))
        continue
    try:
        snapshot = json.load(open(absolute, encoding="utf-8"))
    except Exception:
        print(FS.join((initiative_id, "__snapshot_unreadable__", "", "")))
        continue
    tracker = snapshot.get("tracker")
    issue = (snapshot.get("initiative") or {}).get("issue")
    repository = (snapshot.get("initiative") or {}).get("repository")
    if not (isinstance(repository, str) and REPO_RE.fullmatch(repository)):
        repository = ""
    tracker_str = tracker if isinstance(tracker, str) else ""
    issue_str = str(issue) if isinstance(issue, int) and issue > 0 else ""
    # 这四个字段拼成的一行要靠 \x1f 分隔、靠换行分隔记录；任何一个字段里
    # 混进 \n / \r / \x1f 都会撕裂这一行，被 bash 的按行 read 拆成多条
    # 错位的记录（其中一条会带着空 tracker 落进兜底分支）。这种快照本身
    # 已经不可信，整条按不可读处理，绝不能把撕裂后的残片当成正常记录。
    if any(has_control_char(field) for field in (initiative_id, tracker_str, issue_str, repository)):
        print(FS.join((sanitize_id(initiative_id), "__snapshot_unreadable__", "", "")))
        continue
    if tracker_str:
        print(FS.join((
            initiative_id,
            tracker_str,
            issue_str,
            repository,
        )))
PY
}

gitlab_archived_issue_state() {
  local issue="$1" project raw
  command -v glab >/dev/null 2>&1 || return 0
  if [ -z "$ARCHIVE_GITLAB_PROJECT_ID" ]; then
    project=$(glab repo view --output json 2>/dev/null | python3 -c '
import json,sys
try: print(json.load(sys.stdin)["path_with_namespace"])
except Exception: pass
' 2>/dev/null) || project=""
    [ -n "$project" ] || return 0
    ARCHIVE_GITLAB_PROJECT_ID=$(glab api "projects/${project//\//%2F}" 2>/dev/null | python3 -c '
import json,sys
try: print(json.load(sys.stdin)["id"])
except Exception: pass
' 2>/dev/null) || ARCHIVE_GITLAB_PROJECT_ID=""
  fi
  [ -n "$ARCHIVE_GITLAB_PROJECT_ID" ] || return 0
  raw=$(glab api "projects/$ARCHIVE_GITLAB_PROJECT_ID/issues/$issue" 2>/dev/null) || raw=""
  [ -n "$raw" ] || return 0
  printf '%s' "$raw" | python3 -c '
import json,sys
try: print(json.load(sys.stdin).get("state", ""))
except Exception: pass
' 2>/dev/null || true
}

if [ "$HAS_ARCHIVED_HISTORY" = true ] && command -v python3 >/dev/null 2>&1; then
  while IFS=$'\x1f' read -r ARCHIVE_INITIATIVE ARCHIVE_TRACKER ARCHIVE_ISSUE ARCHIVE_REPOSITORY; do
    case "$ARCHIVE_TRACKER" in
      none) ;;
      __snapshot_unreadable__)
        ARCHIVE_REMOTE_EXTERNAL=true
        ARCHIVE_SNAPSHOT_UNREADABLE="${ARCHIVE_SNAPSHOT_UNREADABLE}${ARCHIVE_SNAPSHOT_UNREADABLE:+、}initiative [${ARCHIVE_INITIATIVE}] 的归档状态快照"
        ;;
      github)
        ARCHIVE_REMOTE_EXTERNAL=true
        case "$ARCHIVE_ISSUE" in
          ''|*[!0-9]*)
            ARCHIVE_REMOTE_UNVERIFIABLE="${ARCHIVE_REMOTE_UNVERIFIABLE}${ARCHIVE_REMOTE_UNVERIFIABLE:+、}GitHub initiative [${ARCHIVE_INITIATIVE}]（缺少 Issue 编号）"
            continue
            ;;
        esac
        if [ -z "$ARCHIVE_REPOSITORY" ]; then
          ARCHIVE_REMOTE_UNVERIFIABLE="${ARCHIVE_REMOTE_UNVERIFIABLE}${ARCHIVE_REMOTE_UNVERIFIABLE:+、}GitHub Epic #${ARCHIVE_ISSUE}（缺少仓库身份）"
          continue
        fi
        if ! archive_remote_verification_enabled; then
          ARCHIVE_REMOTE_UNVERIFIED="${ARCHIVE_REMOTE_UNVERIFIED}${ARCHIVE_REMOTE_UNVERIFIED:+、}GitHub Epic ${ARCHIVE_REPOSITORY}#${ARCHIVE_ISSUE}（未显式授权远端核验）"
          continue
        fi
        ARCHIVE_STATE=$(gh issue view "$ARCHIVE_ISSUE" --repo "$ARCHIVE_REPOSITORY" --json state --jq .state 2>/dev/null || true)
        case "$ARCHIVE_STATE" in
          OPEN|open) ARCHIVE_REMOTE_OPEN="${ARCHIVE_REMOTE_OPEN}${ARCHIVE_REMOTE_OPEN:+、}GitHub Epic ${ARCHIVE_REPOSITORY}#${ARCHIVE_ISSUE}" ;;
          CLOSED|closed|MERGED|merged) ARCHIVE_REMOTE_CLOSED="${ARCHIVE_REMOTE_CLOSED}${ARCHIVE_REMOTE_CLOSED:+、}GitHub Epic ${ARCHIVE_REPOSITORY}#${ARCHIVE_ISSUE}" ;;
          *) ARCHIVE_REMOTE_UNVERIFIED="${ARCHIVE_REMOTE_UNVERIFIED}${ARCHIVE_REMOTE_UNVERIFIED:+、}GitHub Epic ${ARCHIVE_REPOSITORY}#${ARCHIVE_ISSUE}" ;;
        esac
        ;;
      gitlab)
        ARCHIVE_REMOTE_EXTERNAL=true
        case "$ARCHIVE_ISSUE" in
          ''|*[!0-9]*)
            ARCHIVE_REMOTE_UNVERIFIABLE="${ARCHIVE_REMOTE_UNVERIFIABLE}${ARCHIVE_REMOTE_UNVERIFIABLE:+、}GitLab initiative [${ARCHIVE_INITIATIVE}]（缺少 Issue 编号）"
            continue
            ;;
        esac
        if ! archive_remote_verification_enabled; then
          ARCHIVE_REMOTE_UNVERIFIED="${ARCHIVE_REMOTE_UNVERIFIED}${ARCHIVE_REMOTE_UNVERIFIED:+、}GitLab Issue #${ARCHIVE_ISSUE}（未显式授权远端核验）"
          continue
        fi
        ARCHIVE_STATE=$(gitlab_archived_issue_state "$ARCHIVE_ISSUE")
        case "$ARCHIVE_STATE" in
          open|opened|OPEN|OPENED) ARCHIVE_REMOTE_OPEN="${ARCHIVE_REMOTE_OPEN}${ARCHIVE_REMOTE_OPEN:+、}GitLab Issue #${ARCHIVE_ISSUE}" ;;
          closed|CLOSED) ARCHIVE_REMOTE_CLOSED="${ARCHIVE_REMOTE_CLOSED}${ARCHIVE_REMOTE_CLOSED:+、}GitLab Issue #${ARCHIVE_ISSUE}" ;;
          *) ARCHIVE_REMOTE_UNVERIFIED="${ARCHIVE_REMOTE_UNVERIFIED}${ARCHIVE_REMOTE_UNVERIFIED:+、}GitLab Issue #${ARCHIVE_ISSUE}" ;;
        esac
        ;;
      *)
        ARCHIVE_REMOTE_EXTERNAL=true
        ARCHIVE_REMOTE_UNVERIFIED="${ARCHIVE_REMOTE_UNVERIFIED}${ARCHIVE_REMOTE_UNVERIFIED:+、}${ARCHIVE_TRACKER} 条目${ARCHIVE_ISSUE:+ #${ARCHIVE_ISSUE}}"
        ;;
    esac
  done < <(archived_completed_trackers)
fi

# 违规：spec 放错位置
if ls -1 SPEC*.md >/dev/null 2>&1; then
  broken "根目录有 SPEC*.md —— /build 的路径规则只认 spec/ 通配，挪进 spec/"
fi

# 违规：能力图改了，GitHub 上那份投影没跟上
#   能力图是唯一事实源，issue 是它的投影，state.json 记「上次投影时能力图
#   长什么样」。有了这份指纹，「本地改了、投影没跟上」就是纯本地的 hash
#   比对 —— 不打 gh，也不需要语义比对。算法在 hooks/spec-digest.py，
#   **只有那一份**：写指纹的是 /sync-map（模型执行），读的是这里和
#   verify-artifacts；各写各的实现就会算出对不上的 hash，表现是一条
#   关不掉的假警报。
#
#   三道闸各挡一种假断链（三条判据共用）：
#     1. 仅 tracker=github —— 指纹和 modules.<id>.issue 都只有 /sync-map 写，
#        而它是 GitHub 专属；给 gitlab/jira 项目报出去等于给一条执行不了的建议。
#     2. 已落 ≥ 1 个 —— 能力图刚写完还没同步是 Phase 0 的正常中间态，不是断链。
#     3. 指纹字段缺失一律不报 —— 老项目的 state.json 没有 goalDigest/rowDigest，
#        不能因此挨断链（这条在 spec-digest.py 里，输出 null / 空数组）。
if [ "$LOCAL_STAGE" = absent ] && [ "$HAS_MAP" = true ] && [ "$TRACKER" = "github" ] && [ -f "$STATE" ] \
   && command -v python3 >/dev/null 2>&1 && [ -f "${SELF_DIR}/hooks/spec-digest.py" ]; then
  SYNC_JSON=$(python3 "${SELF_DIR}/hooks/spec-digest.py" check \
    "spec/CAPABILITY-MAP.md" "$STATE" 2>/dev/null || true)
  if [ -n "${SYNC_JSON}" ]; then
    # 一次 python3 把三条判据的措辞都拼好；拼不出来就是空串 → 什么都不报。
    SYNC_MSG=$(printf '%s' "${SYNC_JSON}" | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
if not d.get('ok') or d.get('syncedCount',0) < 1: raise SystemExit
out=[]
mis=d.get('missing') or []
if mis:
    out.append('能力图有 %d 个模块，其中 %d 个没落成 issue（%s）—— 能力图改过之后没重跑 /spec-guard:sync-map'
               % (d['mapCount'], len(mis), ', '.join(mis)))
if d.get('goalStale') is True:
    out.append('能力图的「## 目标」段改过，Epic 正文里那份摘要还是旧的 —— /spec-guard:sync-map 刷新')
rs=d.get('rowsStale') or []
if rs:
    out.append('%s 的职责描述改过，对应 issue 正文里那份摘要还是旧的 —— /spec-guard:sync-map 刷新'
               % ('、'.join(rs)))
print('\n'.join(out))
" 2>/dev/null || true)
    # 反方向（能力图删了行、issue 还在，即 extra）**不报**：没有「弃用」这个
    # 状态，「刻意不做了」和「手滑删了一行」在文件上长得一模一样，机器分不出来。
    if [ -n "${SYNC_MSG}" ]; then
      while IFS= read -r ln; do
        [ -n "${ln}" ] && broken "${ln}"
      done < <(printf '%s\n' "${SYNC_MSG}")
    fi
  fi
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
github_sub_issues() {
  python3 - "$1" <<'PY'
import subprocess
import sys

try:
    result = subprocess.run(
        ["gh", "api", "repos/{owner}/{repo}/issues/%s/sub_issues" % sys.argv[1]],
        capture_output=True,
        text=True,
        timeout=2,
    )
except (OSError, subprocess.TimeoutExpired):
    raise SystemExit(1)
if result.returncode == 0:
    sys.stdout.write(result.stdout)
PY
}
if [ "$LOCAL_STAGE" = absent ] && command -v gh >/dev/null 2>&1 \
  && command -v python3 >/dev/null 2>&1 && [ -n "$MODULE_ISSUE" ]; then
  # 必须用 REST sub_issues：`gh issue list` **没有** --parent 这个 flag
  # （--parent 只在 gh issue create 上）。早期版本用了它，结果每次都失败、
  # 静默落进「gh 不可用」降级分支 —— GitHub 层从来没真正跑过。
  RAW=$(github_sub_issues "$MODULE_ISSUE" 2>/dev/null) || RAW=""
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
BRANCH_DISPLAY="$BRANCH"
if [ -z "$BRANCH_DISPLAY" ]; then
  HEAD_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "")
  [ -n "$HEAD_SHORT" ] && BRANCH_DISPLAY="HEAD（detached @ ${HEAD_SHORT}）"
fi
GIT_TOP=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
WORKTREE_DISPLAY=""
if [ -n "$GIT_TOP" ]; then
  if [ -f "$GIT_TOP/.git" ]; then
    WORKTREE_DISPLAY="linked worktree（附加工作区）"
  else
    WORKTREE_DISPLAY="primary checkout"
  fi
fi
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
if [ "$LOCAL_STAGE" = valid ]; then
  PHASE="LOCAL_VALIDATION (tracker 尚未激活)"
  NEXT="按 tasks/${MODULE}/plan.md 的最新检查点说明成果、已授权下一步和下次停点；此状态不授权任务领取或远端写入"
elif [ "$LOCAL_STAGE" != absent ]; then
  PHASE="LOCAL_VALIDATION_INVALID"
  broken "本地验证阶段不可用：${LOCAL_STAGE_RESULT#*|}"
  NEXT="先核对 state 与当前模块 spec/plan；不要自动清除阶段字段或激活 tracker"
elif [ "$HAS_ARCHIVED_HISTORY" = true ]; then
  if [ -n "$ARCHIVE_REMOTE_OPEN" ]; then
    PHASE="ARCHIVE_DRIFT (远端未关闭)"
    broken "本地 history 已归档，但 ${ARCHIVE_REMOTE_OPEN} 仍为 OPEN；本地归档不能代替远端 tracker 的完成态"
    NEXT="先向用户说明本地/远端分歧；获得确认后关闭对应 initiative 条目。远端关闭后，hook 会在下次注入时重新核验"
  elif [ -n "$ARCHIVE_REMOTE_UNVERIFIED" ] || [ -n "$ARCHIVE_SNAPSHOT_UNREADABLE" ]; then
    PHASE="ARCHIVED (远端待核验)"
    NEXT="当前没有活跃 initiative"
    [ -n "$ARCHIVE_SNAPSHOT_UNREADABLE" ] && NEXT="${NEXT}；${ARCHIVE_SNAPSHOT_UNREADABLE} 不可读，先用 /spec-guard:history-integrity 做只读审计并检查对应 checkpoint"
    [ -n "$ARCHIVE_REMOTE_UNVERIFIED" ] && NEXT="${NEXT}；${ARCHIVE_REMOTE_UNVERIFIED} 的远端 tracker 未核验，获得用户明确授权后以 SPEC_GUARD_ARCHIVE_REMOTE_VERIFY=1 运行一次 hook 做只读确认"
    [ -n "$ARCHIVE_REMOTE_UNVERIFIABLE" ] && NEXT="${NEXT}；${ARCHIVE_REMOTE_UNVERIFIABLE} 无法核验（归档时未记录仓库身份或没有 Issue 编号），不影响开始新的一轮"
    NEXT="${NEXT}；处理后再开始新的一轮"
  elif [ -n "$ARCHIVE_REMOTE_UNVERIFIABLE" ]; then
    PHASE="IDLE (已归档，部分无法核验)"
    NEXT="当前没有活跃 initiative；${ARCHIVE_REMOTE_UNVERIFIABLE} 无法核验（归档时未记录仓库身份或没有 Issue 编号），不影响开始新的一轮；/spec 开始新的一轮"
  elif [ "$ARCHIVE_REMOTE_EXTERNAL" = true ]; then
    PHASE="IDLE (已归档，远端已核验)"
    NEXT="当前没有活跃 initiative；已核验归档对应的外部 tracker 条目均关闭，可 /spec 开始新的一轮"
  else
    PHASE="IDLE (已归档)"
    NEXT="当前没有活跃 initiative；/spec 开始新的一轮"
  fi
elif [ "$HAS_MAP" = false ] && [ "$SPEC_COUNT" -eq 0 ]; then
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
    NEXT="/spec-guard:sync-map 把能力图和模块落成 issue"
  else
    NEXT="跑 /spec-guard:setup-convention 建出 .agent/state.json，并把 activeModule 写进去"
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
  # GitLab 有自己的 bridge；其他 tracker 只做到 plan 层。
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
    if [ "$TRACKER" = gitlab ]; then
      NEXT="加载 spec-gitlab-bridge，在 GitLab 中选择可执行 Issue 后 /build"
    else
      NEXT="在 ${TRACKER} 里认领下一个任务后 /build —— 本插件的任务层自动化只覆盖 github、gitlab 和 none"
    fi
  fi

elif [ "$SPEC_COUNT" -gt 0 ] && [ -z "$MODULE_ISSUE" ]; then
  # activeModule 有值却没有对应 issue。真断链。
  # （「连 state.json 都没有」由上面那条单独接住，所以这里 MODULE 必非空。）
  PHASE="SPECED"
  broken "activeModule=[$MODULE] 但 .agent/state.json 里没有它的 issue —— 链路在此断开"
  NEXT="/spec-guard:sync-map 把能力图和模块落成 issue"

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
    NEXT="恢复 gh 后 /spec-guard:next 继续取任务；本分支已落 ${TASKS_DONE_HERE} 个 task"
  elif [ -n "$BRANCH_ISSUE" ] && [ "$DIRTY" -gt 0 ]; then
    PHASE="BUILDING (gh 不可用，降级判定)"
    NEXT="/test 验证 → /spec-guard:deliver 开 PR（有 $DIRTY 处未提交改动）"
  elif [ -n "$BRANCH_ISSUE" ]; then
    PHASE="TASK_READY (gh 不可用，降级判定)"
    NEXT="/spec-guard:deliver 开 PR（Closes #${BRANCH_ISSUE}）"
  else
    PHASE="PLANNED (gh 不可用，降级判定)"
    NEXT="恢复 gh 后 /spec-guard:next；或手动指定要做的 issue"
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
  NEXT="/spec-guard:next 推进到下一个模块（[$MODULE] 已无未关闭任务）"

elif [ "${ON_MODULE_BRANCH}" = true ] && [ "$DIRTY" -gt 0 ]; then
  PHASE="BUILDING (模块分支)"
  NEXT="/test 验证 → 提交（commit message 带 Closes #<task-issue>），有 ${DIRTY} 处未提交改动"

elif [ "${ON_MODULE_BRANCH}" = true ] && [ "$OPEN_TASKS" != "?" ] \
     && [ "${TASKS_DONE_HERE}" -gt 0 ] && [ "${TASKS_DONE_HERE}" -ge "$OPEN_TASKS" ]; then
  PHASE="MODULE_READY"
  NEXT="/spec-guard:deliver 开模块 PR —— [${MODULE}] 的 ${OPEN_TASKS} 个未关闭 task 在本分支都有对应 commit"

elif [ "${ON_MODULE_BRANCH}" = true ]; then
  PHASE="TASK_READY (模块分支)"
  NEXT="/build auto 跑完模块剩下的 task（或 /spec-guard:next 逐条取）——**留在 [${BRANCH}] 上，不要每个 task 开 PR**（已落 ${TASKS_DONE_HERE}/${OPEN_TASKS}）"

elif [ -n "$ASSIGNED" ] && [ -z "$BRANCH_ISSUE" ]; then
  PHASE="TASK_CLAIMED"
  broken "已认领 $ASSIGNED 但当前分支 [$BRANCH] 不含 issue 号，也不属于模块 [${MODULE}] —— 可能在错误分支上工作"
  NEXT="切到模块分支 <type>/${MODULE} 后 /build"

elif [ -n "$BRANCH_ISSUE" ] && [ "$DIRTY" -gt 0 ]; then
  PHASE="BUILDING"
  NEXT="/test 验证 → /spec-guard:deliver 开 PR（有 $DIRTY 处未提交改动）"

elif [ -n "$BRANCH_ISSUE" ] && [ "$DIRTY" -eq 0 ]; then
  PHASE="TASK_READY"
  NEXT="/spec-guard:deliver 开 PR（Closes #${BRANCH_ISSUE}）"

else
  PHASE="PLANNED"
  NEXT="/spec-guard:next 取下一个任务"
fi

# 只在下一步真的会进入 next/deliver 时才检查 binding。MAP_ONLY、缺 plan 等
# 前置阶段还不能消费 binding；此时用它覆盖 /spec 或 /plan 的建议，会把用户
# 引到一个必然失败的命令。真正取任务或交付时仍必须 fail-closed。
NEEDS_WORKSPACE_BINDING=false
case "$NEXT" in
  *"/spec-guard:next"*|*"/spec-guard:deliver"*) NEEDS_WORKSPACE_BINDING=true ;;
esac
if [ "$NEEDS_WORKSPACE_BINDING" = true ] \
   && { [ "$TRACKER" = "github" ] || [ "$TRACKER" = "gitlab" ]; } \
   && [ -n "$MODULE" ] && [ -f "spec/CAPABILITY-MAP.md" ] \
   && grep -q '^Build order:' "spec/CAPABILITY-MAP.md" 2>/dev/null \
   && [ -f "${SELF_DIR}/hooks/workspace_binding.py" ]; then
  BINDING_JSON=$(python3 "${SELF_DIR}/hooks/workspace_binding.py" inspect --project "$ROOT" --format json 2>/dev/null || true)
  BINDING_CODE=$(printf '%s' "$BINDING_JSON" | python3 -c '
import json,sys
try: print(json.load(sys.stdin).get("code", "context-unknown"))
except Exception: print("context-unknown")
' 2>/dev/null)
  if [ "$BINDING_CODE" != "ok" ]; then
    broken "当前 worktree 没有可用的 tracker binding（${BINDING_CODE}）；/next 与 /deliver 必须在选择或写入前停止"
    NEXT="先检查 /spec-guard:bind-workspace；确认 tracker、initiative 与 module 后显式绑定当前 worktree，再继续"
  fi
fi

# ── 组装事实 ───────────────────────────────────────────────
[ -n "$MODULE" ] && add "活跃模块: $MODULE${MODULE_ISSUE:+ (issue #$MODULE_ISSUE)}"
add "tracker: $TRACKER"
add "spec: 能力图=$HAS_MAP, 模块 spec=$SPEC_COUNT 份"
# 指纹脚本的绝对路径。/sync-map 要调它算 digest，而模型的 Bash 里
# **没有 CLAUDE_PLUGIN_ROOT** —— 不注入的话它只能去 find，找错版本就
# 算出对不上的 hash，那正是这套设计最怕的「关不掉的假警报」。
# 纯参数展开，不 fork。
[ -f "${SELF_DIR}/hooks/spec-digest.py" ] \
  && add "spec-digest: ${SELF_DIR}/hooks/spec-digest.py"
[ -f "${SELF_DIR}/references/workflow-checkpoints.md" ] \
  && add "checkpoint-rules: ${SELF_DIR}/references/workflow-checkpoints.md（阶段交接或停止前读取；已有授权不重复询问）"
[ -n "$MODULE" ] && add "plan: tasks/$MODULE/plan.md=$HAS_PLAN"
[ "$OPEN_TASKS" != "?" ] && add "GitHub: $OPEN_TASKS 个未关闭 task（sub-issue 共 ${TOTAL_TASKS} 个）${ASSIGNED:+, 已认领 $ASSIGNED}"
[ -n "$ARCHIVE_REMOTE_CLOSED" ] && add "归档远端核验：${ARCHIVE_REMOTE_CLOSED} 已关闭"
[ -n "$ARCHIVE_REMOTE_UNVERIFIED" ] && add "归档远端核验：${ARCHIVE_REMOTE_UNVERIFIED} 未核验"
[ -n "$ARCHIVE_REMOTE_UNVERIFIABLE" ] && add "归档远端核验：${ARCHIVE_REMOTE_UNVERIFIABLE} 无法核验"
[ -n "$ARCHIVE_SNAPSHOT_UNREADABLE" ] && add "归档状态快照不可读：${ARCHIVE_SNAPSHOT_UNREADABLE}"
[ -n "$BRANCH_DISPLAY" ] && add "git: 分支=$BRANCH_DISPLAY, worktree=${WORKTREE_DISPLAY:-未知}, 未提交=$DIRTY"
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
  if [ "$IS_CODEX" = true ] && [ "$TRACKER" = "github" ]; then
    OUT="${OUT}
**本项目没有 AGENTS.md 声明块（Codex 的 --no-instructions 模式）。**
动 spec、拆任务、取任务或交付之前，先加载 \`spec-github-bridge\` skill ——
目录约定、issue 落库、模块级 PR 与合并策略全在里面。跳过它必然写出双真相源。
"
  elif [ "$IS_CODEX" = true ]; then
    OUT="${OUT}
**本项目没有 AGENTS.md 声明块（Codex 的 --no-instructions 模式）。**
当前 tracker 是「${TRACKER}」；在动 spec 或任务前，先确认项目说明文件中的
spec-guard 约定与当前 tracker 一致，避免把 GitHub 流程套到不对应的 tracker。
"
  elif [ "$TRACKER" = "github" ]; then
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
建议跑 \`/spec-guard:setup-convention local\` 把声明块写回去（13 行）。
"
  fi
fi

OUT="${OUT}
建议下一步: $NEXT

以上是仓库客观状态。若用户意图与之冲突，以用户为准，但要先指出冲突。"

emit "$OUT"
