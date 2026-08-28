#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# next-redo —— 验 0.7.19 修的那条：`/next` 会不会把**刚做完的 task**
#              重新取出来做第二遍
#
#   模块级 PR 约定下 task issue 要到 PR 合入默认分支才关，所以做完的 task
#   在整个模块周期里一直是 open。0.7.19 之前操作三的四条筛选规则没有一条
#   挡得住它：open、不被 blocked、assignee 就是自己 —— 全部放行。
#
#   修法是新增筛选规则 3「排除本分支已经做完的」，号从 phase-guard 注入的
#   事实行里读。但**操作三由模型执行，没有脚本入口** —— 规则写在 skill 文字里，
#   hook 侧有断言，模型侧那一半一直没有任何东西验过。这个脚本补的就是那一半。
#
# 做法：差分。两个脚手架只差一件事 —— 分支上有没有一条 `Closes #110`。
#
#   [对照] fresh  分支干净        → 正确答案 #110（第一个 open 且不被阻塞的）
#   [处理] midway 已落 Closes #110 → 正确答案 #111；取到 #110 就是那个 bug
#
#   判据是**桩记录下来的 gh 调用**，不是 transcript —— 比读模型说了什么客观。
#   对照组同时充当脚手架自检：它要是没取到 #110，说明模型压根没按操作三走，
#   处理组的结果也就无从归因，这时给的是「没跑起来」而不是结论。
#
# ⚠️ 会真的调模型。不接进 validate.sh。
#
# 用法:
#   bash evals/next-redo.sh --scaffold-only    # 免费：只建脚手架 + 查 hook 注入
#   bash evals/next-redo.sh --selftest         # 免费：喂坏输入验判决器自己
#   bash evals/next-redo.sh                    # 真跑
# ─────────────────────────────────────────────────────────────
set -uo pipefail

MODE=run
[ "${1:-}" = "--scaffold-only" ] && MODE=scaffold
[ "${1:-}" = "--selftest" ]      && MODE=selftest

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PLUG="${REPO}/plugins/spec-guard"
WORK="${TMPDIR:-/tmp}/spec-guard-nr-$$"
PROMPT="按约定取下一个任务并认领它。只做取任务这一步，不要开始写代码。"
# shellcheck source=evals/_preflight.sh
. "${HERE}/_preflight.sh"

# ── gh 桩：记录每一次调用，模块 #9 下挂三个 task ──────────────
#   110 111 可取；112 被 111 阻塞（blocked_by=1）——
#   留着它是为了让「取到 112」和「取到 110」在结论里分得开：
#   前者是规则 2 失效，后者才是本次要验的规则 3。
mkgh() {  # $1=桩目录
  mkdir -p "$1"
  cat > "$1/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "${GHLOG}"
case "$*" in
  *sub_issues*)
    cat <<'JSON'
[{"number":110,"state":"open","title":"建 session 表结构","assignees":[],
  "issue_dependencies_summary":{"blocked_by":0,"total_blocked_by":0}},
 {"number":111,"state":"open","title":"实现登录接口","assignees":[],
  "issue_dependencies_summary":{"blocked_by":0,"total_blocked_by":0}},
 {"number":112,"state":"open","title":"接入第三方 OAuth","assignees":[],
  "issue_dependencies_summary":{"blocked_by":1,"total_blocked_by":1}}]
JSON
    ;;
  *"issue view 110"*) echo '{"title":"建 session 表结构","body":"验收：session 表建好并有迁移脚本","parent":{"number":9},"blockedBy":[]}' ;;
  *"issue view 111"*) echo '{"title":"实现登录接口","body":"验收：POST /login 返回 session cookie","parent":{"number":9},"blockedBy":[]}' ;;
  *"issue view 112"*) echo '{"title":"接入第三方 OAuth","body":"验收：可用 GitHub 登录","parent":{"number":9},"blockedBy":[{"number":111}]}' ;;
  *"issue edit"*)     echo "✓ updated" ;;
  *"auth status"*)    echo "Logged in to github.com as tester" ;;
  *)                  echo "" ;;
esac
STUB
  chmod +x "$1/gh"
}

mk() {  # $1=目录 $2=fresh|midway
  rm -rf "$1"; mkdir -p "$1/spec" "$1/tasks/identity" "$1/.agent"
  ( cd "$1" && git init -q )
  {
    printf '# CLAUDE.md\n\n身份服务。构建 `npm run build`，测试 `npm test`。\n\n'
    echo "<!-- BEGIN:agent-skills-convention -->"
    cat "${PLUG}/templates/claude-block-github.md"
    echo "<!-- END:agent-skills-convention -->"
  } > "$1/CLAUDE.md"
  printf '# 能力图\n\n| Module id | 职责 | Depends on |\n|---|---|---|\n| identity | 认证 | — |\n\n- [x] 已评审\n' > "$1/spec/CAPABILITY-MAP.md"
  printf '# identity\n\n验收：用户能注册、登录、登出。会话 30 天过期。\n' > "$1/spec/identity.md"
  printf '# Plan: identity\n\n## Task List\n\n> Tasks tracked in GitHub Issues #9\n\n- #110 建 session 表结构\n- #111 实现登录接口\n- #112 接入第三方 OAuth\n' > "$1/tasks/identity/plan.md"
  echo '{"tracker":"github","activeModule":"identity","initiative":{"issue":8},"modules":{"identity":{"issue":9}}}' > "$1/.agent/state.json"
  ( cd "$1" \
    && git add -A >/dev/null \
    && git -c user.email=t@t -c user.name=t commit -qm init \
    && git checkout -qb feat/identity )
  if [ "$2" = midway ]; then
    ( cd "$1" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat(identity): 建 session 表结构

Closes #110" )
  fi
}

# 桩记下来的调用里，模型认领了哪个号
picked() {  # $1=日志路径 ; 打印 "<号> <信号>"，取不到则打印空
  local n
  n=$(grep -oE 'issue edit [0-9]+ .*add-assignee' "$1" 2>/dev/null \
        | grep -oE '[0-9]+' | head -1)
  if [ -n "${n}" ]; then echo "${n} add-assignee"; return; fi
  # 兜底信号：没认领但看过某个 task 的正文。比 transcript 客观，比 add-assignee 弱，
  # 所以要在结论里标出来是哪一种，不能混着报。
  n=$(grep -oE 'issue view 1[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
  [ -n "${n}" ] && echo "${n} issue-view"
}

# 判决。抽成函数**只为了它自己能被喂坏输入** —— 本仓在「新加的防线自己有
# 毛病」上翻过四次车，四次都是同一个形状：判据写完没有当场用真实数据跑一遍。
# 见 --selftest。
verdict() {  # $1=对照组 picked $2=处理组 picked ; 0=通过 1=不通过 2=没跑起来
  local F="$1" M="$2"
  echo "  [对照 fresh ] 取到: ${F:-（没有任何 issue 调用）}"
  echo "  [处理 midway] 取到: ${M:-（没有任何 issue 调用）}"
  echo ""
  # 「没取到任何东西」和「取错了」是两回事 —— 前者多半是模型没按操作三走，
  # 读成产品缺陷就是拿工具故障去指控产品。
  if [ -z "${F}" ] || [ -z "${M}" ]; then
    echo "  ⏭  有一组没产生任何 issue 调用 —— **没有结论**，不要读成「规则 3 不成立」"
    return 2
  fi
  if [ "${F%% *}" != "110" ]; then
    echo "  ⏭  对照组没取到 #110（取到 ${F%% *}）—— 模型没按操作三走，"
    echo "     处理组的结果无从归因。**没有结论**"
    return 2
  fi
  case "${M%% *}" in
    110) echo "  ❌ 处理组把**刚做完的 #110** 又取了一遍 —— 筛选规则 3 没起作用"
         echo "     这正是 issue #4 的症状：它 open、不被阻塞、assignee 是自己，其余规则全部放行"
         return 1 ;;
    111) echo "  ✅ 处理组跳过 #110，取到 #111 —— 筛选规则 3 成立"
         echo "     （对照组同样条件下取 #110，说明差别确实来自那条 Closes commit）"
         [ "${M#* }" = "issue-view" ] && echo "  ℹ  处理组是靠 issue view 判定的，没走到 --add-assignee —— 信号弱一档"
         return 0 ;;
    112) echo "  ❌ 处理组取到被阻塞的 #112 —— 规则 2 失效（不是本次要验的规则 3）"
         return 1 ;;
    *)   echo "  ⏭  处理组取到 ${M%% *}，不在 110/111/112 之内 —— **没有结论**"
         return 2 ;;
  esac
}

# ── --selftest：不调模型，喂已知输入验 picked() 和 verdict() ──────
#   这一层管的是「评测自己会不会永远打绿灯」。真跑那次两组都过了，
#   但**一个永远返回 0 的判决器也会打出一模一样的输出**。
if [ "${MODE}" = selftest ]; then
  SP=0; SF=0
  st() {  # $1=说明 $2=期望退出码 $3=对照 $4=处理
    local rc; verdict "$3" "$4" >/dev/null 2>&1; rc=$?
    if [ "${rc}" = "$2" ]; then printf '  ✅ %s\n' "$1"; SP=$((SP+1))
    else printf '  ❌ %s（得到 %s，期望 %s）\n' "$1" "${rc}" "$2"; SF=$((SF+1)); fi
  }
  echo "═══ next-redo 自检（不调模型）═══"
  st "处理组取 #111 → 通过"                 0 "110 add-assignee" "111 add-assignee"
  st "处理组把刚做完的 #110 又取一遍 → 不通过" 1 "110 add-assignee" "110 add-assignee"
  st "处理组取到被阻塞的 #112 → 不通过"       1 "110 add-assignee" "112 add-assignee"
  st "对照组就没取到 #110 → 没跑起来，不是结论" 2 "111 add-assignee" "111 add-assignee"
  st "处理组一次调用都没有 → 没跑起来"        2 "110 add-assignee" ""
  st "两组都没调用 → 没跑起来"               2 "" ""
  st "取到不认识的号 → 没跑起来，不算通过"     2 "110 add-assignee" "999 add-assignee"

  # picked() 也要验：它是唯一把桩日志变成结论的地方
  PL="${TMPDIR:-/tmp}/nr-selftest-$$.log"
  printf 'issue view 111 --json title,body\nissue edit 111 --add-assignee @me\n' > "${PL}"
  [ "$(picked "${PL}")" = "111 add-assignee" ] \
    && { printf '  ✅ picked：认领优先于查看\n'; SP=$((SP+1)); } \
    || { printf '  ❌ picked：认领没被优先取到\n'; SF=$((SF+1)); }
  printf 'issue view 110 --json title\nissue view 111 --json title\n' > "${PL}"
  [ "$(picked "${PL}")" = "111 issue-view" ] \
    && { printf '  ✅ picked：没认领时兜底取最后看过的那个，并标弱信号\n'; SP=$((SP+1)); } \
    || { printf '  ❌ picked：兜底信号不对\n'; SF=$((SF+1)); }
  printf 'api repos/{owner}/{repo}/issues/9/sub_issues\n' > "${PL}"
  [ -z "$(picked "${PL}")" ] \
    && { printf '  ✅ picked：只列过 sub_issues 不算取到任何 task\n'; SP=$((SP+1)); } \
    || { printf '  ❌ picked：从 sub_issues 那行里捡出了号（9 或 110）\n'; SF=$((SF+1)); }
  rm -f "${PL}"

  echo ""
  echo "  总计 ${SP} 通过 / ${SF} 失败"
  [ "${SF}" -eq 0 ] || exit 1
  exit 0
fi

if [ "${MODE}" != scaffold ]; then
  preflight_installed_matches_repo "${REPO}" || exit 1
fi

mkdir -p "${WORK}"
mkgh "${WORK}/bin"
mk "${WORK}/fresh"  fresh
mk "${WORK}/midway" midway
echo "  脚手架: ${WORK}"

# hook 必须真的把号注入出来 —— 那是规则 3 的唯一数据来源。
# 注入不出来的话模型无从执行，评测测的是空气。
HCTX=$(GHLOG="${WORK}/hookprobe.log" PATH="${WORK}/bin:${PATH}" \
       CLAUDE_PROJECT_DIR="${WORK}/midway" CLAUDE_PLUGIN_ROOT="${PLUG}" \
       bash "${PLUG}/hooks/phase-guard.sh" 2>/dev/null \
  | python3 -c 'import sys,json
try: print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception: print("")')
case "${HCTX}" in
  *"#110"*) echo "  ✅ hook 在处理组注入了已做完的号（#110）" ;;
  *)        echo "  ❌ hook 没把已做完的号注入出来 —— 规则 3 无数据可用，评测无意义"
            printf '%s\n' "${HCTX}" | sed -n '1,12p' | sed 's/^/     /'
            exit 1 ;;
esac
case "$(GHLOG="${WORK}/hookprobe.log" PATH="${WORK}/bin:${PATH}" \
        CLAUDE_PROJECT_DIR="${WORK}/fresh" CLAUDE_PLUGIN_ROOT="${PLUG}" \
        bash "${PLUG}/hooks/phase-guard.sh" 2>/dev/null)" in
  *"110"*) echo "  ❌ 对照组也注入了 #110 —— 两组没差分开，评测无意义"; exit 1 ;;
  *)       echo "  ✅ 对照组没有已做完的号（两组确实只差这一件事）" ;;
esac

[ "${MODE}" = scaffold ] && { echo "  --scaffold-only：到此为止，未调用模型"; exit 0; }

export PATH="${WORK}/bin:${PATH}"
RUNFAIL=0
for arm in fresh midway; do
  echo "  跑 ${arm} …"
  export GHLOG="${WORK}/${arm}.ghlog"; : > "${GHLOG}"
  run_headless "${WORK}/${arm}" "${WORK}/${arm}.out" \
    -p "${PROMPT}" --max-turns 12 --allowedTools Read Glob Grep Skill Bash \
    || RUNFAIL=1
done
if [ "${RUNFAIL}" -ne 0 ]; then
  echo ""
  echo "  ⏭  评测没跑起来 —— **没有结论**，不要读成「规则 3 不成立」"
  exit 2
fi

echo ""
F=$(picked "${WORK}/fresh.ghlog");  M=$(picked "${WORK}/midway.ghlog")
verdict "${F}" "${M}"
