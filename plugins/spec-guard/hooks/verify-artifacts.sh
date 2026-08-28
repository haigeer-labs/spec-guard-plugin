#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# verify-artifacts.sh —— 产物落地校验（只读）
#
# phase-guard.sh 回答「现在在哪个阶段」，本脚本回答「已经落下的产物对不对」。
#
# 为什么需要它：整套约定从头到尾都是**提示词**——CLAUDE.md 里写「不要创建
# todo.md」、SKILL.md 里写「issue 正文不要粘贴 spec 全文」，全是对模型的建议。
# 软指令必须配硬检测，否则跑歪了没人知道。
#
# 为什么不并进 phase-guard：那个挂在 UserPromptSubmit 上，有 <1s 预算，
# 而这里的检查要读文件内容、打 gh。按需跑，不是每轮跑。
#
# 与 phase-guard 有三项重叠（根目录 SPEC*.md / todo.md 并存 / 分支归属），
# 是刻意的：一个「随时提醒」，一个「按需体检」，体检漏项比重复更糟。
# **重叠项的判定规则必须两边一致** —— 0.6.0 改了模块分支约定却只改了
# phase-guard，verify-artifacts 留在 task 分支时代，直到 0.7.11 才补上。
#
# 退出码: 0=无 FAIL（可能有 WARN）  1=有 FAIL  2=约定未启用
#
# 用法: CLAUDE_PROJECT_DIR=/path/to/project bash verify-artifacts.sh
# ─────────────────────────────────────────────────────────────
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${ROOT}" 2>/dev/null || { echo "❌ 进不去目录: ${ROOT}"; exit 1; }

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

P=0; W=0; F=0
ok()   { printf '  ✅ %s\n' "$1"; P=$((P+1)); }
warn() { printf '  ⚠️  %s\n' "$1"; W=$((W+1)); }
bad()  { printf '  ❌ %s\n' "$1"; F=$((F+1)); }
skip() { printf '  ⏭  %s\n' "$1"; }

# ── 约定未启用就别装懂 ──────────────────────────────────────
# 激活信号两种，满足其一即可：CLAUDE.md 的约定标题，或 .agent/state.json 存在
# （后者是零 CLAUDE.md 足迹模式，见 phase-guard.sh 同处注释）
ACTIVE=false
[ -f CLAUDE.md ] && grep -q "Agent Skills 集成约定" CLAUDE.md 2>/dev/null && ACTIVE=true
[ -f .agent/state.json ] && ACTIVE=true
if [ "$ACTIVE" != true ]; then
  echo "本项目没有启用 spec-guard 约定（CLAUDE.md 缺约定标题，且无 .agent/state.json）。"
  echo "先跑 /setup-convention。"
  exit 2
fi

STATE=".agent/state.json"

jread() {  # $1=file  $2=python 表达式(d 为根对象)
  [ -f "$1" ] || return 0
  python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    v=$2
    print(v if v is not None else '')
except Exception:
    print('')
" "$1" 2>/dev/null
}

# ── tracker 判定（与 phase-guard 同一套顺序）────────────────
TRACKER=$(jread "${STATE}" "d.get('tracker')")
if [ -z "${TRACKER}" ]; then
  R=$(git remote get-url origin 2>/dev/null || echo "")
  case "${R}" in
    *github.com*|*github.*) TRACKER="github" ;;
    "")                     TRACKER="none" ;;
    *)                      TRACKER="other" ;;
  esac
fi
MODULE=$(jread "${STATE}" "d.get('activeModule')")
EPIC=$(jread "${STATE}" "d.get('initiative',{}).get('issue')")

echo "═══ 产物落地校验 ═══"
echo "  tracker=${TRACKER}${MODULE:+  activeModule=${MODULE}}"
echo ""

# ── A. 能力图 ──────────────────────────────────────────────
echo "── A. 能力图 ──"
MAP="spec/CAPABILITY-MAP.md"
MAP_IDS=""
if [ ! -f "${MAP}" ]; then
  warn "${MAP} 不存在 —— 单模块项目可忽略；多模块的话 Phase 0 没落地"
else
  MAP_IDS=$(python3 - "${MAP}" <<'PY'
import re, sys
ids = []
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.lstrip().startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 2:
        continue
    first = cells[0]
    # 跳过表头和 |---|---| 分隔行
    if not first or first.lower() == "module id" or set(first) <= set("-: "):
        continue
    ids.append(first.strip(chr(96)))  # chr(96)=反引号；写字面量会截断外层 $( )
print("\n".join(ids))
PY
)
  N=$(printf '%s' "${MAP_IDS}" | grep -c . || true)
  if [ "${N}" -eq 0 ]; then
    warn "${MAP} 里没解析出任何 module id —— 表格格式可能不对"
  elif grep -q "^example-" <<<"${MAP_IDS}"; then   # herestring：管道 + grep -q 会 SIGPIPE
    warn "${MAP} 还是模板占位符（example-a/example-b），没填真实模块"
  else
    ok "能力图解析出 ${N} 个 module id"
  fi

  # 评审记录没勾完
  if grep -q "^- \[ \]" "${MAP}" 2>/dev/null; then
    warn "能力图的评审记录还有未勾选项 —— Phase 0 是 gated 的，评审不能跳"
  fi

  # module id 必须 kebab-case
  BADID=$(printf '%s' "${MAP_IDS}" | grep -vE '^[a-z0-9]+(-[a-z0-9]+)*$' | grep . || true)
  [ -n "${BADID}" ] && bad "module id 不是 kebab-case: $(printf '%s' "${BADID}" | tr '\n' ' ')"
fi
echo ""

# ── B. spec 文件名 ↔ module id ─────────────────────────────
#   最阴险的一类漂移：能力图写 identity，模型建了 spec/user-identity.md。
#   phase-guard 只数 spec/*.md 的数量，从不比对，所以下游会静默错位。
echo "── B. spec 文件名 ↔ module id ──"
SPECS=$(ls -1 spec/*.md 2>/dev/null | sed 's|^spec/||;s|\.md$||' | grep -v "^CAPABILITY-MAP$" || true)
if [ -z "${MAP_IDS}" ]; then
  skip "无能力图，跳过比对"
elif [ -z "${SPECS}" ]; then
  warn "spec/ 下还没有模块 spec —— Phase 0 走完了但没递归"
else
  ORPHAN=$(comm -13 <(printf '%s\n' "${MAP_IDS}" | sort) <(printf '%s\n' "${SPECS}" | sort) | grep . || true)
  MISSING=$(comm -23 <(printf '%s\n' "${MAP_IDS}" | sort) <(printf '%s\n' "${SPECS}" | sort) | grep . || true)
  if [ -n "${ORPHAN}" ]; then
    bad "spec/ 里有能力图上没有的模块: $(printf '%s' "${ORPHAN}" | tr '\n' ' ')"
    printf '     上游原话：the map, not filename guessing, is the index of what exists\n'
  fi
  [ -n "${MISSING}" ] && printf '  ℹ  能力图上还没写 spec 的模块: %s（按 build order 逐个补）\n' \
    "$(printf '%s' "${MISSING}" | tr '\n' ' ')"
  [ -z "${ORPHAN}" ] && ok "spec 文件名与 module id 一致"
fi
echo ""

# ── C. 目录约定 ────────────────────────────────────────────
echo "── C. 目录约定 ──"
if ls -1 SPEC*.md >/dev/null 2>&1; then
  bad "根目录有 $(ls -1 SPEC*.md | tr '\n' ' ')—— /build 只认 spec/ 通配，挪进 spec/"
else
  ok "根目录无 SPEC*.md"
fi
ROOTFILES=""
for r in tasks/plan.md tasks/todo.md; do
  [ -f "$r" ] && ! is_archived "$r" && ROOTFILES="${ROOTFILES}${r} "
done
if [ -n "${ROOTFILES}" ]; then
  bad "tasks/ 根下有 ${ROOTFILES}—— 缺 module 命名空间，多模块时会互相覆盖"
elif [ -f "tasks/plan.md" ] || [ -f "tasks/todo.md" ]; then
  ok "tasks/ 根下只有已归档文件（不计违规）"
else
  ok "tasks/ 有 module 命名空间"
fi
if [ "${TRACKER}" != "none" ]; then
  T=$(live_todos | grep . || true)
  A=$(find tasks -name "todo.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ -n "${T}" ]; then
    bad "存在 $(printf '%s' "${T}" | tr '\n' ' ') 但已声明外部 tracker —— 二者不能并存，必然分叉"
    printf '     若它是已完成模块的历史记录：在前 10 行内写上「已归档」或 ARCHIVED 即可豁免\n'
  else
    ok "无活的 todo.md 与 tracker 并存$( [ "${A}" -gt 0 ] && echo "（${A} 份已归档，不计）" )"
  fi
fi
echo ""

# ── D. plan.md 内容 ────────────────────────────────────────
echo "── D. plan.md ──"
if [ -z "${MODULE}" ]; then
  skip "state.json 没有 activeModule"
elif [ ! -f "tasks/${MODULE}/plan.md" ]; then
  warn "tasks/${MODULE}/plan.md 不存在 —— /plan 还没跑"
else
  PLAN="tasks/${MODULE}/plan.md"
  if [ "${TRACKER}" = "github" ]; then
    if grep -qE '^\s*- \[[ x]\]' "${PLAN}"; then
      bad "${PLAN} 里有 checkbox —— tracker 模式下 Task List 应是 issue 编号索引，不是 checklist"
    else
      ok "${PLAN} 的 Task List 不是 checklist"
    fi
    grep -qi "tracked in" "${PLAN}" \
      && ok "${PLAN} 注明了 tracker 位置" \
      || warn "${PLAN} 没写「Tasks tracked in ...」—— 跨会话续接会找不到任务在哪"
  else
    ok "${PLAN} 存在"
  fi
fi
echo ""

# ── E. GitHub 层（探测失败就整段跳过，绝不误报）────────────
echo "── E. GitHub 层 ──"
if [ "${TRACKER}" != "github" ]; then
  skip "tracker=${TRACKER}，不涉及 GitHub"
elif ! command -v gh >/dev/null 2>&1; then
  skip "gh 未安装，跳过（不代表通过）"
elif ! gh auth status >/dev/null 2>&1; then
  skip "gh 未认证，跳过（不代表通过）"
else
  # Epic 的 sub-issue 数 == 能力图模块数
  if [ -n "${EPIC}" ] && [ -n "${MAP_IDS}" ]; then
    # REST sub_issues —— `gh issue list` 没有 --parent flag
    SUBN=$(gh api "repos/{owner}/{repo}/issues/${EPIC}/sub_issues" 2>/dev/null \
           | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "")
    MAPN=$(printf '%s' "${MAP_IDS}" | grep -c . || true)
    if [ -z "${SUBN}" ]; then
      skip "读不到 Epic #${EPIC} 的 sub-issue（网络或权限），跳过"
    elif [ "${SUBN}" -ne "${MAPN}" ]; then
      bad "Epic #${EPIC} 有 ${SUBN} 个 sub-issue，能力图有 ${MAPN} 个模块 —— 对不上"
    else
      ok "Epic #${EPIC} 的模块 issue 数与能力图一致（${MAPN}）"
    fi
  else
    skip "state.json 没有 initiative.issue，跳过 Epic 比对"
  fi

  # Epic 正文是否粘贴了能力图全文
  #   这一处到 0.7.19 才有。此前只体检模块 issue 的正文，而**唯一一处流程
  #   明确指示粘贴全文的地方恰恰是 Epic**（操作一步骤 2 原来写的是
  #   `--body-file spec/CAPABILITY-MAP.md`）—— 检查器盖不到发布方自己写的
  #   那条错。规则写在 skill 里，判据落在这里，两边差了一个 issue 的距离。
  #   比的是 Epic 正文 vs 能力图本身，同一份文档，粘贴全文时比值 ≈ 1，
  #   摘要通常远低于 1/3，2/3 这个阈值和模块那处是可比的。
  if [ -n "${EPIC}" ] && [ -f "${MAP}" ]; then
    EBODY=$(gh issue view "${EPIC}" --json body -q '.body' 2>/dev/null || echo "")
    ML=$(wc -c < "${MAP}" | tr -d ' ')
    if [ -z "${EBODY}" ]; then
      skip "读不到 Epic #${EPIC} 的正文（网络/权限，或正文本就是空的），跳过体量比对"
    else
      EL=$(printf '%s' "${EBODY}" | wc -c | tr -d ' ')
      if [ "${ML}" -gt 0 ] && [ "${EL}" -gt $((ML * 2 / 3)) ]; then
        warn "Epic #${EPIC} 正文 ${EL} 字节 vs 能力图 ${ML} 字节 —— 疑似灌了能力图全文，能力图会改，复制必然分叉"
      else
        ok "Epic #${EPIC} 正文是摘要而非能力图全文"
      fi
    fi
  fi

  # 模块 issue 正文是否粘贴了 spec 全文
  MI=$(jread "${STATE}" "d.get('modules',{}).get('${MODULE}',{}).get('issue')")
  if [ -n "${MI}" ] && [ -f "spec/${MODULE}.md" ]; then
    # 读不到正文（被删 / 权限 / 网络）时**必须 skip，不能报 ok**。
    # 原先 gh 失败 → BL=0 → 落进 else → 打出「✅ 正文是摘要而非 spec 全文」,
    # 把「没查成」算成「查过了没问题」。本段段头写的是「探测失败就整段跳过,
    # 绝不误报」,同段另外三处（Epic / 父 issue / PR 正文）都老实 skip,
    # 只有这一处发没挣来的绿灯 —— 而这个脚本存在的意义就是不发这种绿灯。
    IBODY=$(gh issue view "${MI}" --json body -q '.body' 2>/dev/null || echo "")
    SL=$(wc -c < "spec/${MODULE}.md" | tr -d ' ')
    if [ -z "${IBODY}" ]; then
      skip "读不到 issue #${MI} 的正文（网络/权限，或正文本就是空的），跳过体量比对"
    else
      BL=$(printf '%s' "${IBODY}" | wc -c | tr -d ' ')
      if [ "${SL}" -gt 0 ] && [ "${BL}" -gt $((SL * 2 / 3)) ]; then
        warn "issue #${MI} 正文 ${BL} 字节 vs spec ${SL} 字节 —— 疑似粘贴了 spec 全文，spec 会改，复制必然分叉"
      else
        ok "issue #${MI} 正文是摘要而非 spec 全文"
      fi
    fi
  fi

  # 模块的 sub-issue 数 ↔ plan.md 的 Task List 条目数
  #
  # 补这一项是因为「任务落库」此前**完全没有产物校验**：SKILL 的 Verification
  # 里写着「sub_issues 条目数 == plan.md 索引条数」，但没有任何东西真去比。
  # 它一次盖住两种失败：
  #   · 一条 sub-issue 都没有 = 任务从没落库（phase-guard 那边判 PLANNED (任务未落库)）
  #   · 两边对不上 = 落库中途失败后重跑的残留，或 plan.md 没回写全
  if [ -n "${MI}" ] && [ -f "tasks/${MODULE}/plan.md" ]; then
    PN=$(grep -coE '^[[:space:]]*[-*][[:space:]]+#[0-9]+' "tasks/${MODULE}/plan.md" || true)
    [ -z "${PN}" ] && PN=0
    SUBJ=$(gh api "repos/{owner}/{repo}/issues/${MI}/sub_issues" 2>/dev/null \
           | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "")
    if [ -z "${SUBJ}" ]; then
      skip "读不到模块 issue #${MI} 的 sub-issue（网络或权限），跳过任务落库比对"
    elif [ "${PN}" -eq 0 ] && [ "${SUBJ}" -eq 0 ]; then
      warn "tasks/${MODULE}/plan.md 没有 issue 编号索引，#${MI} 下也没有 sub-issue —— 任务还没落库"
    elif [ "${PN}" -eq 0 ]; then
      warn "#${MI} 下有 ${SUBJ} 个 sub-issue，但 plan.md 的 Task List 一个编号都没写 —— 跨会话续接会找不到任务在哪"
    elif [ "${SUBJ}" -eq 0 ]; then
      bad "plan.md 索引了 ${PN} 个 task，但 #${MI} 下一个 sub-issue 都没有 —— 任务从没落库"
    elif [ "${PN}" -ne "${SUBJ}" ]; then
      warn "plan.md 索引 ${PN} 个 task，#${MI} 下有 ${SUBJ} 个 sub-issue —— 对不上（落库中途失败重跑的残留？或 plan.md 没回写全）"
    else
      ok "任务落库数与 plan.md 索引一致（${PN}）"
    fi
  fi

  # 当前分支是模块分支还是 task 分支
  #
  # 0.6.0 把 PR 粒度从 task 提到 module，phase-guard 同步改了，**这里没有** ——
  # 当时误判「verify-artifacts 没有分支逻辑」（grep 找的是 BRANCH，而这里叫 BR）。
  # 后果是模块名自带数字时（`feat/oauth2`）那个 `2` 被当成 issue 号，
  # 报出「PR 正文没有 Closes #2」这种**假失败** —— 而 PR 正文里写的是
  # 正确的 `Closes #<module-issue>`。
  #
  # 判定规则与 phase-guard 一致：**末段整段相等**，不是子串包含。
  BR=$(git branch --show-current 2>/dev/null || echo "")
  ON_MOD=false
  if [ -n "${BR}" ] && [ -n "${MODULE}" ]; then
    case "${BR}" in "${MODULE}"|*/"${MODULE}") ON_MOD=true ;; esac
  fi
  BRI=""
  [ "${ON_MOD}" = false ] && BRI=$(printf '%s' "${BR}" | grep -oE '[0-9]+' | head -1 || true)

  if [ "${ON_MOD}" = true ]; then
    # 模块分支：PR 正文该关的是**模块 issue**；task issue 靠 commit message 关
    PRB=$(gh pr view --json body -q '.body' 2>/dev/null || echo "")
    if [ -z "${PRB}" ]; then
      skip "模块分支 ${BR} 还没有 PR（模块跑完再开）"
    elif grep -qiE "closes #${MI}\b" <<<"${PRB}"; then
      ok "模块 PR 正文含 Closes #${MI}"
    else
      bad "模块 PR 正文没有 Closes #${MI} —— 模块 issue 不会自动关闭"
    fi
    BASE=""
    for b in main master; do
      git show-ref --verify --quiet "refs/heads/${b}" && { BASE="$b"; break; }
    done
    if [ -n "${BASE}" ] && [ "${BASE}" != "${BR}" ]; then
      NC=$(git log -n 200 --format=%B "${BASE}..HEAD" 2>/dev/null \
        | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#[0-9]+' \
        | grep -oE '[0-9]+' | sort -u | grep -c . || true)
      [ -z "${NC}" ] && NC=0
      if [ "${NC}" -gt 0 ]; then
        ok "本分支 ${NC} 条 commit 带 closing keyword（task issue 靠它们关）"
      else
        warn "本分支没有一条 commit 带 Closes #<task-issue> —— 合并后 task issue 不会关"
      fi
    fi
  elif [ -n "${BRI}" ]; then
    # task 分支（老约定，仍然支持）
    PRB=$(gh pr view --json body -q '.body' 2>/dev/null || echo "")
    if [ -z "${PRB}" ]; then
      skip "分支 ${BR} 还没有 PR"
    elif grep -qiE "closes #${BRI}\b" <<<"${PRB}"; then
      ok "PR 正文含 Closes #${BRI}"
    else
      bad "PR 正文没有 Closes #${BRI} —— issue 不会自动关闭，Project 看板不流转"
    fi
  fi

  # activeModule 与当前分支是否对得上
  if [ -n "${BRI}" ] && [ -n "${MI}" ]; then
    PAR=$(gh issue view "${BRI}" --json parent -q '.parent.number' 2>/dev/null || echo "")
    if [ -z "${PAR}" ]; then
      skip "读不到 #${BRI} 的父 issue，跳过归属校验"
    elif [ "${PAR}" != "${MI}" ]; then
      bad "分支在做 #${BRI}（父 #${PAR}），但 activeModule=${MODULE} 的 issue 是 #${MI} —— 对不上"
    else
      ok "当前分支的 task 属于 activeModule"
    fi
  fi
fi

echo ""
echo "═══ ${P} 通过 / ${W} 警告 / ${F} 失败 ═══"
if [ "${F}" -gt 0 ]; then
  echo ""
  echo "失败项要先向用户说明再处理，不要自作主张补齐 —— 有些是用户故意的。"
  exit 1
fi
exit 0
