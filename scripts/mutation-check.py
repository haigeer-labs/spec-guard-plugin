#!/usr/bin/env python3
"""往两个 hook 里注入似是而非的回归，看断言套件抓不抓得住。

存在的理由：0.7.20 撞见过三条**空断言** —— 它们要验的变量为空时也照样通过，
而且全绿。那次是靠另一个测试红了才顺藤发现的。靠撞见不是办法。

「活下来的变异体」= 一个没人拦得住的改动方向。它不一定是 bug，但它一定
说明那条路径上没有断言。

不接进 validate.sh：每个变异体要跑一遍整套，几分钟起步。
用法: python3 scripts/mutation-check.py [--only <关键词>]
"""
import subprocess, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
H = os.path.join(ROOT, "plugins/spec-guard/hooks")
PG, VA = os.path.join(H, "phase-guard.sh"), os.path.join(H, "verify-artifacts.sh")
TPG, TVA = os.path.join(H, "test-phase-guard.sh"), os.path.join(H, "test-verify-artifacts.sh")

# 每条: (说明, 被改的文件, 跑哪套, old, new, 预期)
#   预期 "killed"     = 必须被抓到
#   预期 "equivalent" = 行为等价，**活下来才对**
# 标 equivalent 必须写清楚为什么 —— 否则它就是给漏测发的免死金牌。
M = [
  ("模块分支匹配放宽成子串包含（master 会被当成模块 a 的分支）", PG, TPG,
   '''    "${MODULE}"|*/"${MODULE}") ON_MODULE_BRANCH=true ;;''',
   '''    *"${MODULE}"*) ON_MODULE_BRANCH=true ;;''', "killed"),
  # 裁决为行为等价：状态机里每一处 BRANCH_ISSUE 的使用都排在
  # `ON_MODULE_BRANCH = true` 的分支之后，模块分支上根本走不到。
  # 那个 guard 是防御性的，不是承重的 —— 真正管这件事的是**分支顺序**，
  # 而顺序有「module id 带数字仍认模块分支」那条断言盯着。
  # 与其为一个等价变异硬加一条空断言，不如把裁决写下来。
  ("先捡 issue 号、再判模块分支（0.7.12 修过的那个顺序）", PG, TPG,
   '''[ "${ON_MODULE_BRANCH}" = false ] \\\n  && BRANCH_ISSUE=''',
   '''true \\\n  && BRANCH_ISSUE=''', "equivalent"),
  ("已做完的 task 号不去重（个数会偏大）", PG, TPG,
   """      | grep -oE '[0-9]+' | sort -u || true)""",
   """      | grep -oE '[0-9]+' || true)""", "killed"),
  ("注入的号不带 # 前缀", PG, TPG,
   """DONE_LIST=$(printf '%s' "${DONE_NUMS}" | sed 's/^/#/' | tr '\\n' ' ')""",
   """DONE_LIST=$(printf '%s' "${DONE_NUMS}" | tr '\\n' ' ')""", "killed"),
  ("default_base 不问 origin/HEAD（0.7.20 修的那条）", PG, TPG,
   '''  h=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)''',
   '''  h=""''', "killed"),
  ("default_base 去掉远端跟踪 ref 兜底", PG, TPG,
   '''  if [ -n "${h}" ] && git show-ref --verify --quiet "refs/remotes/${h}"; then echo "${h}"; return; fi''',
   '''  :''', "killed"),
  ("「一个 sub-issue 都没有」重新被当成「任务都做完了」", PG, TPG,
   '''elif [ "$OPEN_TASKS" = "0" ] && [ "$TOTAL_TASKS" = "0" ]; then''',
   '''elif [ "$OPEN_TASKS" = "zzz" ]; then''', "killed"),
  ("归档豁免看前 200 行而不是前 10 行", PG, TPG,
   """  grep -qiE '已归档|ARCHIVED' <<<"$(head -10 "$1" 2>/dev/null)\"""",
   """  grep -qiE '已归档|ARCHIVED' <<<"$(head -200 "$1" 2>/dev/null)\"""", "killed"),
  ("能力图↔已落 issue：去掉「至少已落 1 个」这道闸（Phase 0 中间态会挨假断链）", PG, TPG,
   '''  if [ "${SYNCEDN}" -ge 1 ] && [ "${MAPN}" -gt "${SYNCEDN}" ]; then''',
   '''  if [ "${MAPN}" -gt "${SYNCEDN}" ]; then''', "killed"),
  ("能力图↔已落 issue：去掉 tracker=github 这道闸（本地模式会挨假断链）", PG, TPG,
   '''if [ "$HAS_MAP" = true ] && [ "$TRACKER" = "github" ] && [ -f "$STATE" ] \\''',
   '''if [ "$HAS_MAP" = true ] && [ -f "$STATE" ] \\''', "killed"),
  ("零足迹激活信号（state.json）被去掉", PG, TPG,
   '''[ -f ".agent/state.json" ] && ACTIVE=true''',
   '''true''', "killed"),
  ("Epic 正文体量阈值放宽到 3 倍（等于不查）", VA, TVA,
   '''      if [ "${ML}" -gt 0 ] && [ "${EL}" -gt $((ML * 2 / 3)) ]; then''',
   '''      if [ "${ML}" -gt 0 ] && [ "${EL}" -gt $((ML * 3)) ]; then''', "killed"),
  ("模块 issue 正文读不到时发绿灯而不是 skip", VA, TVA,
   '''      skip "读不到 issue #${MI} 的正文（网络/权限，或正文本就是空的），跳过体量比对"''',
   '''      ok "issue #${MI} 正文是摘要而非 spec 全文"''', "killed"),
  ("plan.md 条目数与 sub-issue 数对不上时不再报", VA, TVA,
   '''    elif [ "${PN}" -ne "${SUBJ}" ]; then''',
   '''    elif false; then''', "killed"),
  ("认不出基准分支时回到静默（0.7.20 修的那条）", VA, TVA,
   '''      skip "认不出默认分支（试过 origin/HEAD、main、master、init.defaultBranch），跳过 closing keyword 比对"''',
   '''      :''', "killed"),
]
def green(suite):
    r = subprocess.run(["/bin/bash", suite], capture_output=True, text=True)
    return r.returncode == 0 and " 0 失败" in r.stdout


# 基线：没变异的时候套件必须是绿的。
# 不查这一条的话，套件路径写错 / 环境坏掉会让 subprocess 直接非零退出，
# 而本脚本把「非零」读成「变异被抓到」—— **13 个全绿，一次都没真测**。
# 这正是本仓 lenses B5 说的那种「分不清没跑起来和跑了但不对」。
BASE_OK = {}

only = None
if "--only" in sys.argv:
    only = sys.argv[sys.argv.index("--only") + 1]

killed, survived, stale = [], [], []
for desc, f, suite, old, new, expect in M:
    if only and only not in desc:
        continue
    src = open(f, encoding="utf-8").read()
    if old not in src:
        stale.append(desc)
        print(f"  ⚠️  锚点失效: {desc}", flush=True)
        continue
    if suite not in BASE_OK:
        BASE_OK[suite] = green(suite)
        print(f"  {'基线绿' if BASE_OK[suite] else '⛔ 基线就不是绿的'}: {os.path.basename(suite)}", flush=True)
    if not BASE_OK[suite]:
        stale.append(f"{desc}（基线不绿，本条没测）")
        continue
    try:
        open(f, "w", encoding="utf-8").write(src.replace(old, new, 1))
        r = subprocess.run(["/bin/bash", suite], capture_output=True, text=True)
        # 套件自己打「N 失败」，退出码也非零；两个都看，别只信一个
        died = r.returncode != 0 or " 0 失败" not in r.stdout
    finally:
        open(f, "w", encoding="utf-8").write(src)
    good = died if expect == "killed" else not died
    (killed if good else survived).append(f"{desc}"
        + ("" if expect == "killed" else "（预期等价）"))
    mark = "✅ 抓到" if died else ("✅ 如期等价" if expect != "killed" else "❌ 活下来")
    if died and expect != "killed":
        mark = "⚠️  本以为等价却被抓到了（好事，但裁决过期了）"
    print(f"  {mark}: {desc}", flush=True)

print()
print(f"  符合预期 {len(killed)} / 不符 {len(survived)} / 锚点失效 {len(stale)}")
if survived:
    print("\n  不符预期的变异体 —— 这些路径上没有断言：")
    for d in survived:
        print(f"    · {d}")
sys.exit(1 if (survived or stale) else 0)
