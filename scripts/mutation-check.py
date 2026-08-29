#!/usr/bin/env python3
"""往两个 hook 里注入似是而非的回归，看断言套件抓不抓得住。

存在的理由：0.7.20 撞见过三条**空断言** —— 它们要验的变量为空时也照样通过，
而且全绿。那次是靠另一个测试红了才顺藤发现的。靠撞见不是办法。

「活下来的变异体」= 一个没人拦得住的改动方向。它不一定是 bug，但它一定
说明那条路径上没有断言。

不接进 validate.sh：每个变异体要跑一遍整套，几分钟起步。
用法: python3 scripts/mutation-check.py [--only <关键词>]
"""
import atexit, signal, subprocess, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
H = os.path.join(ROOT, "plugins/spec-guard/hooks")
PG, VA = os.path.join(H, "phase-guard.sh"), os.path.join(H, "verify-artifacts.sh")
DG = os.path.join(H, "spec-digest.py")   # 指纹算法：两个 hook 和 /sync-map 共用的那一份
TPG, TVA = os.path.join(H, "test-phase-guard.sh"), os.path.join(H, "test-verify-artifacts.sh")

# ── 安全闸：这个工具**在工作区就地改文件** ────────────────────
#   实测踩过：它在后台跑的时候，另一边跑测试读到的是被注入变异的
#   phase-guard.sh，得到一条假失败；而 `git diff` 里躺着的
#   `rows.append((mid, mid))` 差点被 commit 出去 —— 那是个坏掉的指纹算法。
#   两道闸各挡一种：
#     1. 锁文件 —— 不许两个实例、也提醒别在跑的时候干别的
#     2. 目标文件必须干净 —— 否则「你的改动」和「上一次没还原的变异」分不开
#   另加 SIGTERM/SIGINT 兜底还原：try/finally 挡不住被 kill。
LOCK = os.path.join(ROOT, ".mutation-check.lock")


def _die(msg):
    print(msg)
    sys.exit(2)


if os.path.exists(LOCK):
    try:
        pid = open(LOCK).read().strip()
    except Exception:
        pid = "?"
    _die("  ⛔ 已有一个 mutation-check 在跑（pid %s）。\n"
         "     它会就地改 hooks/ 里的文件，两个实例同时跑必然互相污染。\n"
         "     确认没在跑就删掉 %s" % (pid, LOCK))

TARGETS = [PG, VA, DG]
# **只列真脏的那个。** 把三个全列出来是误导性报错 —— 读的人会去看两个
# 根本没动过的文件。管得太宽的判据和管得太窄的一样是缺陷（lenses A3）。
_dirty = [t for t in TARGETS if subprocess.run(
    ["git", "-C", ROOT, "diff", "--quiet", "HEAD", "--", t]).returncode != 0]
if _dirty:
    _die("  ⛔ 这些将被变异的文件相对 HEAD 不干净：\n"
         "     " + "  ".join(os.path.relpath(t, ROOT) for t in _dirty) + "\n"
         "     跑之前必须干净 —— 否则跑完还原时会把你自己的改动一起抹掉，\n"
         "     而且中途 `git diff` 里的东西分不清是你写的还是注入的变异。\n"
         "     先 commit 或 stash。")

open(LOCK, "w").write(str(os.getpid()))


def _cleanup(*_a):
    # 还原所有目标文件 + 删锁。被 kill 时 try/finally 不会跑，这里兜住。
    subprocess.run(["git", "-C", ROOT, "checkout", "--"] + TARGETS,
                   capture_output=True)
    try:
        os.remove(LOCK)
    except OSError:
        pass


atexit.register(_cleanup)
for _sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(_sig, lambda *_a: sys.exit(130))

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
  ("指纹：去掉「至少已落 1 个」这道闸（Phase 0 中间态会挨假断链）", PG, TPG,
   '''if not d.get('ok') or d.get('syncedCount',0) < 1: raise SystemExit''',
   '''if not d.get('ok'): raise SystemExit''', "killed"),
  ("指纹：去掉 tracker=github 这道闸（gitlab 项目会收到执行不了的建议）", PG, TPG,
   '''if [ "$HAS_MAP" = true ] && [ "$TRACKER" = "github" ] && [ -f "$STATE" ] \\''',
   '''if [ "$HAS_MAP" = true ] && [ -f "$STATE" ] \\''', "killed"),
  ("指纹：把「判不了」也当成「过期了」（老项目会挨假断链）", PG, TPG,
   '''if d.get('goalStale') is True:''',
   '''if d.get('goalStale') is not False:''', "killed"),
  ("指纹：模块行只 hash id，不 hash 整行（改职责就查不出来了）", DG, TPG,
   '''        rows.append((mid, "|".join([mid] + cells[1:])))''',
   '''        rows.append((mid, mid))''', "killed"),
  ("指纹：没存 rowDigest 时也判成过期（老项目会挨假断链）", DG, TPG,
   '''        if not stored:
            continue               # 没存指纹 → 判不了 → 不报''',
   '''        if not stored:
            stored = "always-stale"''', "killed"),
  ("重复 Epic：撤掉列表截断检测（窗口外的重复会被打成绿灯）", VA, TVA,
   """    elif len(items)>=201:""",
   """    elif False:""", "killed"),
  ("重复 Epic：标题比较改回压缩空白（宽松比较，与文档声明的逐字相同不符）", VA, TVA,
   """    dups=[str(i.get('number')) for i in items if str(i.get('number'))!=epic and (i.get('title') or '')==t]""",
   """    dups=[str(i.get('number')) for i in items if str(i.get('number'))!=epic and norm(i.get('title'))==norm(t)]""", "killed"),
  ("指纹：verify 这边不再跳过 example-* 占位符", VA, TVA,
   '''if not d.get('ok'):
    print('SKIP|能力图没解析出真实模块（空表或 example-* 占位符）'); raise SystemExit''',
   '''if False:
    print('SKIP|能力图没解析出真实模块（空表或 example-* 占位符）'); raise SystemExit''', "killed"),
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
  ("重复 Epic：标题比较放宽成「Initiative: 开头就算」（不同名的两个 initiative 会挨假失败）", VA, TVA,
   '''    dups=[str(i.get('number')) for i in items if str(i.get('number'))!=epic and (i.get('title') or '')==t]''',
   '''    dups=[str(i.get('number')) for i in items if str(i.get('number'))!=epic and norm(i.get('title')).lower().startswith('initiative:')]''', "killed"),
  ("重复 Epic：不排除记录在案的那个号（每个装了约定的项目都会被报重复）", VA, TVA,
   '''    dups=[str(i.get('number')) for i in items if str(i.get('number'))!=epic and (i.get('title') or '')==t]''',
   '''    dups=[str(i.get('number')) for i in items if (i.get('title') or '')==t]''', "killed"),
  ("重复 Epic：读不到 open issue 列表时发绿灯而不是 skip", VA, TVA,
   '''    skip "读不到 open issue 列表（网络或权限），跳过重复 Epic 比对（不代表通过）"''',
   '''    ok "没有与 Epic #${EPIC} 同名的其他 open issue"''', "killed"),
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
