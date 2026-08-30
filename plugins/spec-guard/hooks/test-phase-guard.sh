#!/usr/bin/env bash
# phase-guard.sh 回归测试
# 用法: bash plugins/spec-guard/hooks/test-phase-guard.sh
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGDIR="$(cd "$HOOKDIR/.." && pwd)"
H="$HOOKDIR/phase-guard.sh"
[ -f "$H" ] || { echo "找不到 $H"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

base() {
  rm -rf "$TMP/r"; mkdir -p "$TMP/r"; cd "$TMP/r" || exit 1
  git init -q 2>/dev/null
  printf '%s\n' '<!-- BEGIN:agent-skills-convention -->' \
    '<!-- END:agent-skills-convention -->' > CLAUDE.md
  git add -A >/dev/null 2>&1
  git -c user.email=t@t -c user.name=t commit -qm init 2>/dev/null
}

phase() {
  CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null | python3 -c '
import sys, json, re
try:
    c = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
    p = re.search(r"当前阶段: \*\*(.+?)\*\*", c).group(1)
    n = len(re.findall("⚠", c))
    print(f"{p}|断链{n}")
except Exception:
    print("(无输出)")'
}

chk() {
  local got; got="$(phase)"
  if [ "$got" = "$2" ]; then
    printf '  ✅ %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  ❌ %s\n     得到 [%s]\n     期望 [%s]\n' "$1" "$got" "$2"; FAIL=$((FAIL+1))
  fi
}

# 取注入正文（不是只取「阶段|断链数」）—— 本套断言长期只比对那两项，
# 正文里的畸形输出因此躺了很久（见上面双斜杠那条注释）。
# 只取「模块分支:」那一行。**不能拿整段 ctx 去 grep 号** ——
# gh 桩给 11 号挂了 assignee，事实行里那句「已认领 #11 T1」照样含 #11，
# 于是断言即使在 DONE_LIST 为空时也会通过。第一版就是这么写的，
# 三条 develop 断言全是空的、全绿。
modline() { ctx | grep "模块分支:" || true; }

ctx() {
  CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null | python3 -c '
import sys, json
try: print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception: print("")'
}

echo "═══ phase-guard 回归测试 ═══"

base
chk "空仓库" "IDLE|断链0"

base; mkdir -p spec; touch spec/CAPABILITY-MAP.md
chk "只有能力图" "MAP_ONLY|断链1"

# 没有 state.json 就无从知道活跃模块，断链措辞要说这件事本身。
# 0.7.12 之前这两条落进本地模式分支，报的是「有 spec 但没有 tasks//plan.md」
# —— 双斜杠是 MODULE="" 拼出来的。而本套断言只比对「阶段|断链数」，
# 从不看正文，所以那个畸形路径在 52 条断言底下躺了很久。
base; mkdir -p spec; touch spec/CAPABILITY-MAP.md spec/a.md
chk "有 spec 但无 state.json" "SPECED|断链1"

base; touch SPEC.md; mkdir -p spec; touch spec/a.md
chk "根目录SPEC + 无 state.json" "SPECED|断链2"

base; mkdir -p spec tasks/x .agent; touch spec/a.md tasks/x/todo.md
echo '{"tracker":"github","activeModule":"x","modules":{"x":{"issue":9}}}' > .agent/state.json
chk "todo并存+无plan" "TRACKED|断链2"

base; mkdir -p spec tasks/x .agent; touch spec/a.md tasks/x/plan.md
echo '{"tracker":"github","activeModule":"x","modules":{"x":{"issue":9}}}' > .agent/state.json
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm p 2>/dev/null
git checkout -qb fix/9-abc 2>/dev/null
chk "干净待交付" "TASK_READY (gh 不可用，降级判定)|断链0"
echo x > f
chk "有改动" "BUILDING (gh 不可用，降级判定)|断链0"

base; mkdir -p spec tasks/x .agent; touch spec/a.md tasks/x/plan.md tasks/x/todo.md
echo '{"tracker":"none","activeModule":"x","modules":{"x":{}}}' > .agent/state.json
chk "本地模式齐全" "READY (本地模式)|断链0"

base; mkdir -p spec .agent; touch spec/a.md
echo '{"tracker":"none","activeModule":"x","modules":{"x":{}}}' > .agent/state.json
chk "本地模式缺plan" "SPECED (本地模式)|断链1"

# state.json 在、activeModule 空 = 刻意空闲，不是断链
base; mkdir -p spec .agent; touch spec/a.md spec/b.md
echo '{"tracker":"github","activeModule":"","modules":{}}' > .agent/state.json
chk "有 spec 但刻意无活跃模块 → 不报断链" "IDLE (无活跃模块)|断链0"

# activeModule 有值却没 issue = 真断链
base; mkdir -p spec .agent; touch spec/a.md
echo '{"tracker":"github","activeModule":"x","modules":{}}' > .agent/state.json
chk "activeModule 有值但无 issue → 真断链" "SPECED|断链1"

# 文案要指名道姓,不能只说「没有模块 issue」
base; mkdir -p spec .agent; touch spec/a.md
echo '{"tracker":"github","activeModule":"x","modules":{}}' > .agent/state.json
if grep -q "activeModule=\[x\]" <<<"$(CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null)"; then
  printf '  ✅ 断链文案指名 activeModule\n'; PASS=$((PASS+1))
else
  printf '  ❌ 断链文案未指名 activeModule\n'; FAIL=$((FAIL+1))
fi

# ── 显式声明的非 GitHub tracker：只做到 plan 层，且不许给 GitHub 专属建议 ──
gl() {  # $1=state.json
  base; mkdir -p spec tasks/x .agent; touch spec/a.md tasks/x/plan.md
  git remote add origin https://gitlab.com/a/b.git 2>/dev/null
  echo "$1" > .agent/state.json
  git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm p 2>/dev/null
}
gl '{"tracker":"gitlab","activeModule":"x","modules":{"x":{"issue":42}}}'
chk "gitlab 齐全 → PLANNED (gitlab)" "PLANNED (gitlab)|断链0"

gl '{"tracker":"jira","activeModule":"x","modules":{"x":{"issue":"AUTH-7"}}}'
chk "jira 齐全 → PLANNED (jira)" "PLANNED (jira)|断链0"

gl '{"tracker":"gitlab","activeModule":"x","modules":{"x":{}}}'
chk "gitlab 缺条目号 → 真断链" "SPECED (gitlab)|断链1"

# 反向：整份注入里不许出现 GitHub 专属说法。
# 「gh 不可用 / 恢复 gh」对 GitLab 项目是指向一个无关的东西，
# 「/sync-map」更糟 —— 那个命令会去 gh 建 GitHub issue。
GLOUT=""
for st in '{"tracker":"gitlab","activeModule":"x","modules":{"x":{"issue":42}}}' \
          '{"tracker":"gitlab","activeModule":"x","modules":{"x":{}}}' \
          '{"tracker":"jira","activeModule":"x","modules":{"x":{"issue":"AUTH-7"}}}'; do
  gl "$st"
  GLOUT="${GLOUT}$(CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null)"
done
BADHIT=""
case "$GLOUT" in *"sync-map"*) BADHIT="/sync-map" ;; esac
case "$GLOUT" in *'gh \u4e0d\u53ef\u7528'*|*"gh 不可用"*) BADHIT="${BADHIT} gh不可用" ;; esac
if [ -z "$BADHIT" ]; then
  printf '  ✅ 非 GitHub tracker 不出现 GitHub 专属建议\n'; PASS=$((PASS+1))
else
  printf '  ❌ 非 GitHub tracker 仍出现:%s\n' "$BADHIT"; FAIL=$((FAIL+1))
fi

base; mkdir -p spec .agent; touch spec/a.md
git remote add origin https://gitlab.com/a/b.git 2>/dev/null
echo '{"activeModule":"x","modules":{"x":{}}}' > .agent/state.json
chk "GitLab未声明tracker" "SPECED (非 GitHub tracker)|断链1"

rm -rf "$TMP/r2"; mkdir -p "$TMP/r2"; echo "# 普通项目" > "$TMP/r2/CLAUDE.md"
if [ -z "$(CLAUDE_PROJECT_DIR="$TMP/r2" bash "$H" 2>/dev/null)" ]; then
  printf '  ✅ 未启用仓库静默\n'; PASS=$((PASS+1))
else
  printf '  ❌ 未启用仓库不该有输出\n'; FAIL=$((FAIL+1))
fi

if [ -z "$(CLAUDE_PROJECT_DIR="$TMP/nope" bash "$H" 2>/dev/null)" ]; then
  printf '  ✅ 目录不存在不崩\n'; PASS=$((PASS+1))
else
  printf '  ❌ 目录不存在时不该有输出\n'; FAIL=$((FAIL+1))
fi

# ── 模块级 PR 约定 ─────────────────────────────────────────
# 这一组必须让 GitHub 层**真的跑起来**：模块分支不含 issue 号，
# 而「已认领但分支不含 issue 号」那条断链只在 GH_OK=true 时才走得到。
# 落进降级分支的话，这组测试测的是空气。
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/bin/bash
cat <<'JSON'
[{"number":11,"state":"open","title":"T1","assignees":[{"login":"me"}]},
 {"number":12,"state":"open","title":"T2","assignees":[]}]
JSON
STUB
chmod +x "$TMP/bin/gh"
OLDPATH="$PATH"
export PATH="$TMP/bin:$PATH"

mod_repo() {  # 建一个「spec+plan+issue 齐全、活跃模块=x」的仓库
  base; mkdir -p spec tasks/x .agent; touch spec/a.md tasks/x/plan.md
  echo '{"tracker":"github","activeModule":"x","modules":{"x":{"issue":9}}}' > .agent/state.json
  git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm p 2>/dev/null
}

mod_repo; git checkout -qb feat/x 2>/dev/null
chk "模块分支干净 → 继续取任务，不报断链" "TASK_READY (模块分支)|断链0"

echo x > f
chk "模块分支有改动 → 提交，不是开 PR" "BUILDING (模块分支)|断链0"

mod_repo; git checkout -qb feat/x 2>/dev/null
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: T1

Closes #11" 2>/dev/null
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: T2

Closes #12" 2>/dev/null
chk "模块内 task 全部落 commit → 该开模块 PR 了" "MODULE_READY|断链0"

# ── /next 不能把刚做完的 task 再取一遍（issue #4）────────────
# 模块级 PR 下 task issue 要到 PR 合入才关：做完的 task 在整个模块周期里
# 一直是 open，操作三那几条筛选规则一条都挡不住它。号一直在 hook 手里
# （TASKS_DONE_HERE 就是数它数出来的），只是从来没往外露过 ——
# **数据在手里、判据没用它**，和 0.7.15 那个 MODULE_DONE 是同一个形状。
mod_repo; git checkout -qb feat/x 2>/dev/null
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: T1

Closes #11" 2>/dev/null
MB="$(modline)"
if case "$MB" in *"#11"*) true ;; *) false ;; esac \
   && case "$MB" in *"#12"*) false ;; *) true ;; esac; then
  printf '  ✅ 模块分支：注入已做完的 task 号（#11），没有牵连未做的 #12\n'; PASS=$((PASS+1))
else
  printf '  ❌ 已做完的 task 号没注入 —— /next 会把它重新取出来做第二遍\n'; FAIL=$((FAIL+1))
fi
chk "落了 1/2 个 task → 仍在取任务，不报断链" "TASK_READY (模块分支)|断链0"

# 反向：一条 closing commit 都没有时不能凭空冒出个号
mod_repo; git checkout -qb feat/x 2>/dev/null
if case "$(modline)" in *"还没有带 closing keyword 的 commit"*) true ;; *) false ;; esac; then
  printf '  ✅ 模块分支无 closing commit：说「还没有」，不列号\n'; PASS=$((PASS+1))
else
  printf '  ❌ 空集合时的措辞不对（列了个空号或者干脆没说）\n'; FAIL=$((FAIL+1))
fi

# 反向：默认分支不叫 main/master 时 BASE 取不到 —— 集合为空要表现为
# 「这条规则不排除任何东西」，**不能**反过来被当成「全做完了」。
# 后者会在这类仓库上一个 task 都取不出来，而且看起来像模块已完成。
mod_repo; git branch -m trunk 2>/dev/null; git checkout -qb feat/x 2>/dev/null
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: T1

Closes #11" 2>/dev/null
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: T2

Closes #12" 2>/dev/null
chk "BASE 取不到时不排除任何 task（不能判成模块已完成）" "TASK_READY (模块分支)|断链0"

# 默认分支不叫 main/master 时，号也必须算得出来。
# 只认这两个名字的话，develop / trunk 仓库上 0.7.19 那条筛选规则拿不到任何
# 数据 —— 「刚做完的 task 被重新取一遍」在这些仓库上原样存在。
# 实测取证：develop 仓库上 hook 说「还没有带 closing keyword 的 commit」，
# 而分支上确实有一条。
setup_remote() {  # 在当前仓库上造一个 origin，并把 origin/HEAD 指到 $1
  # 裸仓库必须用 -b 建：不然它的 HEAD 指着一个不存在的 main，
  # `git remote set-head -a` 会报 "Cannot determine remote HEAD" 并且**静默失败**
  # （加了 >/dev/null 2>&1），origin/HEAD 根本没设上。
  rm -rf "$TMP/o.git"; git init -q --bare -b "$1" "$TMP/o.git" 2>/dev/null
  git remote add origin "$TMP/o.git" 2>/dev/null
  git push -q origin "$1" 2>/dev/null
  git remote set-head origin -a >/dev/null 2>&1
  git show-ref --verify --quiet refs/remotes/origin/HEAD \
    || { printf '  ❌ 脚手架没设上 origin/HEAD，下面三条测的是空气\n'; FAIL=$((FAIL+1)); }
}
mod_repo; git branch -m develop 2>/dev/null; setup_remote develop
git checkout -qb feat/x 2>/dev/null
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: T1

Closes #11" 2>/dev/null
if case "$(modline)" in *"#11"*) true ;; *) false ;; esac; then
  printf '  ✅ 默认分支 develop：靠 origin/HEAD 认出 base，号照样算得出\n'; PASS=$((PASS+1))
else
  printf '  ❌ 默认分支不叫 main/master 时号算不出来 —— 筛选规则拿不到数据\n'; FAIL=$((FAIL+1))
fi

# 本地那条 develop 被删掉，只剩远端跟踪 ref —— 仍要算得出来
git branch -D develop >/dev/null 2>&1
if case "$(modline)" in *"#11"*) true ;; *) false ;; esac; then
  printf '  ✅ 只剩 origin/develop（本地分支已删）也认得出 base\n'; PASS=$((PASS+1))
else
  printf '  ❌ 本地没有那条分支时 base 认不出来\n'; FAIL=$((FAIL+1))
fi

# 反向：常见仓库（有本地 main）的解析结果不能被这次扩展改掉。
# 扩展只该往外扩覆盖面，不该动已有行为。
mod_repo; git branch -m main 2>/dev/null; git checkout -qb feat/x 2>/dev/null
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: T1

Closes #11" 2>/dev/null
if case "$(modline)" in *"#11"*) true ;; *) false ;; esac; then
  printf '  ✅ 本地 main 的常见情形不受影响\n'; PASS=$((PASS+1))
else
  printf '  ❌ 扩展 base 探测把常见情形弄坏了\n'; FAIL=$((FAIL+1))
fi

# 同一个 issue 号被两条 commit 认领（amend 后重提、revert 再来一遍）
# 只能算**一个** task。不去重的话 DONE=2 ≥ OPEN_TASKS=2 → 提前判 MODULE_READY，
# 劝人在模块只做完一半时就开 PR。变异测试（去掉 sort -u）活下来暴露的。
mod_repo; git checkout -qb feat/x 2>/dev/null
for m in "feat: T1 第一版" "feat: T1 返工"; do
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "${m}

Closes #11" 2>/dev/null
done
chk "同一个号出现两次只算一个 task（不能提前判 MODULE_READY）" "TASK_READY (模块分支)|断链0"
if case "$(modline)" in *"已落 1 个"*) true ;; *) false ;; esac; then
  printf '  ✅ 重复的 Closes #11 只数一次\n'; PASS=$((PASS+1))
else
  printf '  ❌ 重复的 Closes 被数了两次 —— 会提前劝人开 PR\n'; FAIL=$((FAIL+1))
fi

# ── 「任务从没建过」不能被当成「任务都做完了」──────────────
# 两者在 OPEN_TASKS 上长得一模一样（都是 0）。此前 phase-guard 一律判
# MODULE_DONE，反过来劝人「推进到下一个模块」——**一个 task 都没做的模块
# 被宣告完成**。成因是 skill 的四个操作里只有「操作二：任务落库」没有命令
# 触发（一/三/四 分别是 /sync-map、/next、/deliver），/plan 跑完没有下一步指路。
cat > "$TMP/bin/gh" <<'STUB0'
#!/bin/bash
echo '[]'
STUB0
chmod +x "$TMP/bin/gh"
mod_repo; chk "plan 写了但一个 sub-issue 都没建 → 不是 MODULE_DONE" "PLANNED (任务未落库)|断链1"

# 正向对照：确实建过、且全部关闭 → 才是 MODULE_DONE
cat > "$TMP/bin/gh" <<'STUB1'
#!/bin/bash
echo '[{"number":11,"state":"closed","title":"T1","assignees":[]},
       {"number":12,"state":"closed","title":"T2","assignees":[]}]'
STUB1
chmod +x "$TMP/bin/gh"
mod_repo; chk "建过且全部关闭 → MODULE_DONE" "MODULE_DONE|断链0"

# 还原给后面用例的桩
cat > "$TMP/bin/gh" <<'STUB'
#!/bin/bash
cat <<'JSON'
[{"number":11,"state":"open","title":"T1","assignees":[{"login":"me"}]},
 {"number":12,"state":"open","title":"T2","assignees":[]}]
JSON
STUB
chmod +x "$TMP/bin/gh"

# 反向用例：真的在错误分支上（不是模块分支、也没 issue 号）仍然要报
mod_repo
chk "已认领却停在默认分支 → 真断链照报" "TASK_CLAIMED|断链1"

# module id 自带数字时，分支名里那串数字不能被当成 task issue 号。
# 0.7.12 之前判定顺序是「先捡号、有号就不判模块」，于是 `feat/oauth2` 里的
# `2` 让模块分支判定整条失效，接着在模块分支上建议「/deliver 开 PR
# （Closes #2）」—— 号是从分支名里捡的，跟这个模块毫无关系。
base; mkdir -p spec tasks/oauth2 .agent; touch spec/a.md tasks/oauth2/plan.md
echo '{"tracker":"github","activeModule":"oauth2","modules":{"oauth2":{"issue":9}}}' > .agent/state.json
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm p 2>/dev/null
git checkout -qb feat/oauth2 2>/dev/null
chk "module id 带数字仍认模块分支（feat/oauth2 的 2 不是 issue 号）" "TASK_READY (模块分支)|断链0"

# 正向对照：真正的 task 分支（老约定）仍按 issue 号判定，不能被这次调整弄回归
mod_repo; git checkout -qb feat/11-login 2>/dev/null
chk "task 分支仍按 issue 号判定（老约定不回归）" "TASK_READY|断链0"

# 反向用例：module id 是单字母时，"master" 不能被当成模块分支
base; mkdir -p spec tasks/a .agent; touch spec/a.md tasks/a/plan.md
echo '{"tracker":"github","activeModule":"a","modules":{"a":{"issue":9}}}' > .agent/state.json
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm p 2>/dev/null
git checkout -qb master 2>/dev/null || git checkout -q master 2>/dev/null
chk "module id=a 时 master 不算模块分支（子串陷阱）" "TASK_CLAIMED|断链1"

export PATH="$OLDPATH"

# ── 「刻意空闲」豁免必须覆盖本地模式 ───────────────────────
# 0.7.12 之前这条豁免排在 tracker 分支**之后**，tracker=none 根本够不到，
# 落进本地模式分支报出「有 spec 但没有 tasks//plan.md」+「/plan 为 [] 拆解任务」
# —— 路径里那个双斜杠和空的 [] 就是 MODULE="" 漏出来的。
# 而本地模式没有任何命令负责给**第一个**模块设 activeModule（/sync-map 是
# github 专属），所以这是本地模式跑完 /spec 的必经状态，不是边角料。
base; mkdir -p spec .agent; touch spec/CAPABILITY-MAP.md spec/a.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
chk "本地模式 activeModule 为空 → 刻意空闲，不是断链" "IDLE (无活跃模块)|断链0"

# 正向对照：有 activeModule 却缺 plan，断链照报（豁免不能扩大化）
base; mkdir -p spec .agent; touch spec/CAPABILITY-MAP.md spec/a.md
echo '{"tracker":"none","activeModule":"a"}' > .agent/state.json
chk "本地模式有活跃模块却缺 plan → 真断链照报" "SPECED (本地模式)|断链1"

# 反向：连 state.json 都没有是真断链，但措辞不能把空 MODULE 拼进路径
base; mkdir -p spec; touch spec/CAPABILITY-MAP.md spec/a.md
OUT_NS="$(CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null)"
case "$OUT_NS" in
  *'tasks//plan.md'*|*'为 []'*)
    printf '  ❌ 空 activeModule 漏进了路径或建议\n'; FAIL=$((FAIL+1)) ;;
  *'没有 .agent/state.json'*)
    printf '  ✅ 无 state.json → 报的是真问题，不拼空模块名\n'; PASS=$((PASS+1)) ;;
  *)
    printf '  ❌ 无 state.json 时的断链措辞不对\n'; FAIL=$((FAIL+1)) ;;
esac

# ── 归档识别不能被大文件搞挂 ───────────────────────────────
# is_archived 原来写的是 `head -10 | grep -qiE`，正是本仓明令禁止的
# 「cmd | grep -q」：grep 命中即关管道，head 吃 SIGPIPE(141)，pipefail 传出
# → 归档豁免失效 → 假违规。实测门槛是前 10 行约 256KB。
mk_todo() {  # $1=首行前缀
  base; mkdir -p spec tasks/x .agent; touch spec/a.md tasks/x/plan.md
  python3 -c "import sys;open('tasks/x/todo.md','w').write(sys.argv[1]+'y'*400000+chr(10))" "$1"
  echo '{"tracker":"github","activeModule":"x","modules":{"x":{"issue":9}}}' > .agent/state.json
}

mk_todo '已归档 '
case "$(CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null)" in
  *"二者不能并存"*) printf '  ❌ 前10行超大的已归档 todo.md 被误报成并存\n'; FAIL=$((FAIL+1)) ;;
  *)                printf '  ✅ 前10行超大的已归档 todo.md 仍被豁免\n'; PASS=$((PASS+1)) ;;
esac

# 正向对照：同样大、但**没有**归档声明的，必须照报
mk_todo '活的清单 '
case "$(CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null)" in
  *"二者不能并存"*) printf '  ✅ 同样大但没归档声明的 todo.md 照报并存\n'; PASS=$((PASS+1)) ;;
  *)                printf '  ❌ 大文件把并存检测整个吞掉了\n'; FAIL=$((FAIL+1)) ;;
esac

# 反向：第 10 行之后的「已归档」不算数。
# 只认前 10 行是刻意的 —— 正文里偶然提到「已归档」不能让整个清单被豁免。
# verify-artifacts 那边早有这条用例，**这边一直没有**：变异测试把
# `head -10` 改成 `head -200`，整套 68 条断言一条都没红。
base; mkdir -p spec tasks/x .agent; touch spec/a.md tasks/x/plan.md
{ printf '# Todo\n'; for i in $(seq 15); do echo "- [ ] t$i"; done; echo "备注：本模块稍后已归档"; } > tasks/x/todo.md
echo '{"tracker":"github","activeModule":"x","modules":{"x":{"issue":9}}}' > .agent/state.json
case "$(CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null)" in
  *"二者不能并存"*) printf '  ✅ 第 10 行之后的「已归档」不算数\n'; PASS=$((PASS+1)) ;;
  *)                printf '  ❌ 正文里提一句「已归档」就把整个清单豁免了\n'; FAIL=$((FAIL+1)) ;;
esac

# ── 零足迹模式要把触发指令补回来 ──
# 实测依据：evals 的 B 组(= 这个模式)hook 正常激活但模型全程没加载 skill。
# hook 注入的是状态，而让 skill 被加载的是那句指令 —— 少了它这个模式就是陷阱。

rm -rf "$TMP/r"; mkdir -p "$TMP/r/.agent"; cd "$TMP/r" || exit 1; git init -q 2>/dev/null
echo "# 普通项目（没有约定标题）" > CLAUDE.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
if case "$(ctx)" in *"spec-github-bridge"*) true ;; *) false ;; esac; then
  printf '  ✅ 零足迹：注入「先加载 spec-github-bridge」\n'; PASS=$((PASS+1))
else
  printf '  ❌ 零足迹下没注入触发指令 —— --no-claude-md 会退化成没有约定\n'; FAIL=$((FAIL+1))
fi

base   # 有当前 Claude 约定声明块
CLAUDE_CTX="$(ctx)"
if case "$CLAUDE_CTX" in *"没有 CLAUDE.md 声明块（零足迹模式）"*) false ;; *) true ;; esac \
   && case "$CLAUDE_CTX" in *"当前阶段"*) true ;; *) false ;; esac; then
  printf '  ✅ Claude 声明块适配器：不报零足迹且照常注入当前阶段\n'; PASS=$((PASS+1))
else
  printf '  ❌ Claude 声明块适配器没有保留原有契约\n'; FAIL=$((FAIL+1))
fi

# 旧版项目只留下约定标题，没有新声明标记；这仍是 Claude 的有效激活信号。
rm -rf "$TMP/r"; mkdir -p "$TMP/r"; cd "$TMP/r" || exit 1
printf '# Agent Skills 集成约定\n' > CLAUDE.md
LEGACY_CLAUDE_CTX="$(ctx)"
if case "$LEGACY_CLAUDE_CTX" in *"当前阶段"*) true ;; *) false ;; esac \
   && case "$LEGACY_CLAUDE_CTX" in *"零足迹模式"*) false ;; *) true ;; esac; then
  printf '  ✅ 旧版 Claude 约定标题仍独立激活\n'; PASS=$((PASS+1))
else
  printf '  ❌ 旧版 Claude 约定标题被误判为未启用\n'; FAIL=$((FAIL+1))
fi

# Codex 只写 AGENTS.md；它是完整的启用信号，不该误落到 Claude 的零足迹分支。
rm -rf "$TMP/codex-phase"; mkdir -p "$TMP/codex-phase"; cd "$TMP/codex-phase" || exit 1
git init -q 2>/dev/null
printf '%s\n' '<!-- BEGIN:spec-guard-codex-convention -->' \
  '<!-- END:spec-guard-codex-convention -->' > AGENTS.md
CODEX_CTX="$(CLAUDE_PROJECT_DIR="$TMP/codex-phase" bash "$H" 2>/dev/null | python3 -c '
import json, sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception: print("")')"
if case "$CODEX_CTX" in *"当前阶段"*) true ;; *) false ;; esac \
   && case "$CODEX_CTX" in *"零足迹模式"*) false ;; *) true ;; esac; then
  printf '  ✅ Codex AGENTS.md 声明块：照常注入当前阶段且不报 Claude 零足迹\n'; PASS=$((PASS+1))
else
  printf '  ❌ Codex AGENTS.md 声明块没有成为独立启用信号\n'; FAIL=$((FAIL+1))
fi

# Codex 的 --no-instructions 不写 AGENTS.md，仍由 state.json 激活；它不能
# 落进 Claude 零足迹文案或推荐 Claude slash command。
rm -rf "$TMP/codex-state"; mkdir -p "$TMP/codex-state/.agent"; cd "$TMP/codex-state" || exit 1
git init -q 2>/dev/null
echo '{"tracker":"github","activeModule":"","modules":{}}' > .agent/state.json
CODEX_STATE_CTX="$(PLUGIN_ROOT="$PLUGDIR" CLAUDE_PROJECT_DIR="$TMP/codex-state" bash "$H" 2>/dev/null | python3 -c '
import json, sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception: print("")')"
if case "$CODEX_STATE_CTX" in *"当前阶段"*) true ;; *) false ;; esac \
   && case "$CODEX_STATE_CTX" in *"CLAUDE.md"*|*"/setup-convention"*) false ;; *) true ;; esac \
   && case "$CODEX_STATE_CTX" in *"Codex"*"--no-instructions"*) true ;; *) false ;; esac; then
  printf '  ✅ Codex state-only：照常注入阶段，不泄露 Claude 指引\n'; PASS=$((PASS+1))
else
  printf '  ❌ Codex state-only 文案混入 Claude 指引或未给 Codex 指令\n'; FAIL=$((FAIL+1))
fi

# 普通 AGENTS.md 不能因为提到 agent 而误激活。
cd "$TMP/codex-phase" || exit 1
printf '# Agent notes\n' > AGENTS.md
if [ -z "$(CLAUDE_PROJECT_DIR="$TMP/codex-phase" bash "$H" 2>/dev/null)" ]; then
  printf '  ✅ 普通 AGENTS.md 无完整 Codex 标记仍静默\n'; PASS=$((PASS+1))
else
  printf '  ❌ 普通 AGENTS.md 被误激活\n'; FAIL=$((FAIL+1))
fi

# 本地模式零足迹：不能指向 spec-github-bridge —— 那个 skill 全篇是 gh issue,
# 对 tracker=none 的项目毫无意义,指过去只会让它去建根本不存在的 issue
rm -rf "$TMP/r"; mkdir -p "$TMP/r/.agent"; cd "$TMP/r" || exit 1; git init -q 2>/dev/null
echo "# 普通项目" > CLAUDE.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
LCTX="$(ctx)"
if case "$LCTX" in *"spec-github-bridge\` skill 里"*) true ;; *) false ;; esac \
   && case "$LCTX" in *"本地模式没有对应的 skill"*) true ;; *) false ;; esac; then
  printf '  ✅ 本地模式零足迹：给的是「把块写回去」而不是「加载 github skill」\n'; PASS=$((PASS+1))
else
  printf '  ❌ 本地模式零足迹的提示不对\n'; FAIL=$((FAIL+1))
fi


# ── hook 自报版本 ──
# 注意不能直接 grep 原始输出:emit() 有 jq 和 python3 两条路径,
# python3 那条会把中文转义成 \uXXXX,grep 中文字面量抓不到。必须解 JSON。
ver() {
  CLAUDE_PROJECT_DIR="$TMP/r" CLAUDE_PLUGIN_ROOT="${1:-}" bash "$H" 2>/dev/null | python3 -c '
import sys, json, re
try:
    c = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
    m = re.search(r"spec-guard: (.+)", c)
    print(m.group(1).strip() if m else "(无版本行)")
except Exception:
    print("(无输出)")'
}

base
GOT="$(ver)"
if [ "$GOT" = "开发副本（未经 /plugin 安装）" ]; then
  printf '  ✅ 未安装时自报「开发副本」\n'; PASS=$((PASS+1))
else
  printf '  ❌ 未安装时的版本行是 [%s]\n' "$GOT"; FAIL=$((FAIL+1))
fi

GOT="$(ver /x/spec-guard/9.9.9)"
if [ "$GOT" = "v9.9.9" ]; then
  printf '  ✅ 从安装路径解析出版本号\n'; PASS=$((PASS+1))
else
  printf '  ❌ 安装路径下的版本行是 [%s]\n' "$GOT"; FAIL=$((FAIL+1))
fi

# ── 失败必须可观察 ──────────────────────────────────────────
# 第一次实跑的教训是「一个永远在降级的探测器和一个坏掉的探测器没区别」。
# 同一句话对「崩掉的」也成立:0.7.8 之前 hooks.json 结尾是 `|| true`,
# 脚本非零退出被吞掉,宿主收到空输出 —— 和「未启用」一模一样。
HJ="$PLUGDIR/hooks/hooks.json"
HCMD=$(python3 -c "
import json,sys
print(json.load(open(sys.argv[1]))['hooks']['UserPromptSubmit'][0]['hooks'][0]['command'])" "$HJ")

rm -rf "$TMP/hk"; mkdir -p "$TMP/hk/crash/hooks" "$TMP/hk/ok/hooks"
printf '#!/bin/bash\nexit 3\n' > "$TMP/hk/crash/hooks/phase-guard.sh"
printf '#!/bin/bash\nexit 0\n' > "$TMP/hk/ok/hooks/phase-guard.sh"

CR=$(CLAUDE_PLUGIN_ROOT="$TMP/hk/crash" CLAUDE_PROJECT_DIR="$TMP/hk" bash -c "$HCMD" 2>/dev/null)
if printf '%s' "$CR" | python3 -c 'import sys,json;c=json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"];sys.exit(0 if "执行失败" in c else 1)' 2>/dev/null; then
  printf '  ✅ hook 崩溃时输出合法 JSON 并说明失败\n'; PASS=$((PASS+1))
else
  printf '  ❌ hook 崩溃被静默吞掉（和「未启用」分不开）\n'; FAIL=$((FAIL+1))
fi

OK=$(CLAUDE_PLUGIN_ROOT="$TMP/hk/ok" CLAUDE_PROJECT_DIR="$TMP/hk" bash -c "$HCMD" 2>/dev/null)
if [ -z "$OK" ]; then
  printf '  ✅ 静默退 0 时确实无输出（未启用的正常表现）\n'; PASS=$((PASS+1))
else
  printf '  ❌ 未启用时不该有输出\n'; FAIL=$((FAIL+1))
fi

# emit():jq 和 python3 都没有时,宁可静默也不能吐半截 JSON。
# 原先是无条件 printf 拼 JSON,python3 一失败命令替换就是空,吐出 {"...":}
rm -rf "$TMP/nobin"; mkdir -p "$TMP/nobin"
for b in bash git grep sed find ls wc tr head cat; do
  BP=$(command -v "$b" 2>/dev/null) && ln -sf "$BP" "$TMP/nobin/$b" 2>/dev/null
done
base
NB=$(PATH="$TMP/nobin" CLAUDE_PROJECT_DIR="$TMP/r" /bin/bash "$H" 2>/dev/null)
if [ -z "$NB" ]; then
  printf '  ✅ 无 jq 无 python3 时静默（不吐半截 JSON）\n'; PASS=$((PASS+1))
else
  printf '  ❌ 无编码器时输出了 [%s]\n' "$NB"; FAIL=$((FAIL+1))
fi

# ── 能力图 ↔ 投影的三处分叉（指纹比对）────────────────────
#   能力图是唯一事实源，issue 是投影，state.json 记「上次投影时能力图长什么样」。
#   十二条里**八条是反向的**：这组检测的全部风险在假断链，不在漏报。
DIGEST="$HOOKDIR/spec-digest.py"

mkmap() {  # $1=目标段（写 - 表示不要这一节）  余下=「id|职责|依赖」
  local goal="$1"; shift
  mkdir -p spec tasks/identity
  {
    echo "# Capability Map: sim"
    echo ""
    if [ "$goal" != "-" ]; then echo "## 目标"; echo ""; echo "$goal"; echo ""; fi
    echo "## 模块"
    echo ""
    echo "| Module id | Responsibility | Depends on |"
    echo "|---|---|---|"
    local r
    for r in "$@"; do
      printf '| `%s` | %s | %s |\n' "${r%%|*}" "$(echo "$r" | cut -d'|' -f2)" "$(echo "$r" | cut -d'|' -f3)"
    done
  } > spec/CAPABILITY-MAP.md
  touch spec/identity.md tasks/identity/plan.md
}

# 拿 spec-digest.py 自己算出「完全同步」的 state.json ——
# 写指纹和读指纹走同一份实现，这正是这套设计的前提。
mksynced() {
  python3 - "$DIGEST" spec/CAPABILITY-MAP.md > .agent/state.json <<'PY'
import json, subprocess, sys
cur = json.loads(subprocess.run([sys.executable, sys.argv[1], "compute", sys.argv[2]],
                                capture_output=True, text=True).stdout)
print(json.dumps({
    "tracker": "github", "activeModule": "identity",
    "initiative": {"issue": 100, "goalDigest": cur["goalDigest"]},
    "modules": {r["id"]: {"issue": 101 + i, "rowDigest": r["rowDigest"]}
                for i, r in enumerate(cur["rows"])},
}, ensure_ascii=False))
PY
}

# 只取这组检测报出来的断链，压成一个紧凑标签。
# ctx 为空时给 EMPTY 而不是「无」—— 否则八条反向断言在「hook 根本没输出」时
# 也全绿，那正是 0.7.20 撞见的空断言形状。
syncwarn() {
  local c; c="$(ctx)"
  [ -n "$c" ] || { echo "EMPTY"; return; }
  printf '%s\n' "$c" | python3 -c "
import sys, re
tags=[]
for l in sys.stdin:
    if '没落成 issue' in l:
        tags.append('missing:' + (re.search(r'（(.+?)）', l).group(1) if re.search(r'（(.+?)）', l) else '?'))
    elif '「## 目标」段改过' in l: tags.append('goal')
    elif '职责描述改过' in l:
        tags.append('rows:' + re.sub(r'^\s*⚠\s*', '', l).split(' 的职责')[0])
print(','.join(tags) if tags else '无')"
}

sw() {  # $1=说明  $2=期望标签
  local got; got="$(syncwarn)"
  if [ "$got" = "$2" ]; then
    printf '  ✅ %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  ❌ %s\n     得到 [%s]\n     期望 [%s]\n' "$1" "$got" "$2"; FAIL=$((FAIL+1))
  fi
}

R2A='identity|登录注册|—'
R2B='catalog|商品上架|identity'
G='给小店主一个能自己上架、自己收款的后台。'

base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B"; mksynced
sw "同步态：什么都不报" "无"

# ① 加了模块（0.7.22 就能查的那条）
mkmap "$G" "$R2A" "$R2B" 'payments|下单与收款|catalog'
sw "① 能力图加了 payments → 报出是哪个，不只是数量" "missing:payments"

# ① 的新能力：数量相等的改名 / 等量增删。旧版按数量比，这里完全查不出来。
base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B"; mksynced
mkmap "$G" "$R2A" 'katalog|商品上架|identity'
sw "① 改名（数量不变）→ 仍报出来（旧版按数量比查不到）" "missing:katalog"

# ③ 只改职责描述：id 集合没变
base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B"; mksynced
mkmap "$G" 'identity|登录注册、会话、找回密码|—' "$R2B"
sw "③ 改职责描述 → 报对应 issue 正文过期" "rows:identity"

# ② 只改目标段
base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B"; mksynced
mkmap '改成给连锁店用。' "$R2A" "$R2B"
sw "② 改「## 目标」段 → 报 Epic 正文过期" "goal"

# 三处一起改
base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B"; mksynced
mkmap '改成给连锁店用。' 'identity|登录注册、会话、找回密码|—' "$R2B" 'payments|收款|catalog'
sw "三处同时改 → 三条都报，各说各的" "missing:payments,goal,rows:identity"

# ── 以下全部是反向 ────────────────────────────────────────

# 闸门 3：老项目的 state.json 没有指纹字段，不能因此挨断链
base; mkdir -p .agent; mkmap '改成给连锁店用。' 'identity|登录注册、会话、找回密码|—' "$R2B"
echo '{"tracker":"github","activeModule":"identity","initiative":{"issue":100},"modules":{"identity":{"issue":101},"catalog":{"issue":102}}}' > .agent/state.json
sw "反：老 state.json 没存指纹 → 目标段和职责都改了也不报（向后兼容）" "无"

# 能力图没有 `## 目标` 段（老能力图），但 state 里存着 goalDigest
base; mkdir -p .agent; mkmap "-" "$R2A" "$R2B"
echo '{"tracker":"github","activeModule":"identity","initiative":{"issue":100,"goalDigest":"deadbeefcafe"},"modules":{"identity":{"issue":101},"catalog":{"issue":102}}}' > .agent/state.json
sw "反：能力图没有「## 目标」段 → 不拿存着的指纹硬比" "无"

# 闸门 2：能力图刚写完，一个都还没落
base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B" 'payments|收款|catalog'
echo '{"tracker":"github","activeModule":"identity","modules":{}}' > .agent/state.json
sw "反：一个都还没落（Phase 0 中间态）→ 不报" "无"

# 闸门 1：本地模式
base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B" 'payments|收款|catalog'
echo '{"tracker":"none","activeModule":"identity","modules":{}}' > .agent/state.json
sw "反：本地模式 tracker=none → 不报" "无"

# 闸门 1 的承重点：非 GitHub tracker 且手写了条目号。
# 上面那条 modules 是 {}，被闸门 2 就挡住了，去掉 tracker=github 也照样绿
# （0.7.22 变异测试实测活下来过）。真正只有闸门 1 拦得住的是这一条：
# 数目确实对不上，但 /sync-map 是 GitHub 专属，报出去是一条执行不了的建议。
base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B" 'payments|收款|catalog'
echo '{"tracker":"gitlab","activeModule":"identity","modules":{"identity":{"issue":11},"catalog":{"issue":12}}}' > .agent/state.json
sw "反：gitlab + 已手写条目号 → 不报（/sync-map 是 GitHub 专属）" "无"

# 反方向：能力图删了行、issue 还在（extra）。没有「弃用」状态，
# 「刻意不做了」和「手滑删了一行」在文件上长得一模一样。
base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B"; mksynced
mkmap "$G" "$R2A"
sw "反：能力图删了一行、issue 还在 → 不报（分不出刻意还是手滑）" "无"

# 半写入：有 key 没 issue 号，算没落成
base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B"; mksynced
python3 -c "
import json; p='.agent/state.json'; d=json.load(open(p))
d['modules']['catalog']={}   # 建到一半挂了
json.dump(d, open(p,'w'))"
sw "有 key 没 issue 号 → 算没落成，报出来" "missing:catalog"

# 探测失败：state.json 不是 JSON
base; mkdir -p .agent; mkmap "$G" "$R2A" "$R2B"
printf '{{{ not json' > .agent/state.json
sw "反：state.json 坏掉 → 不报（探测失败就降级）" "无"

# 还是模板占位符
base; mkdir -p .agent; mkmap "$G" 'example-a|...|—' 'example-b|...|example-a'
echo '{"tracker":"github","activeModule":"identity","modules":{"example-a":{"issue":101}}}' > .agent/state.json
sw "反：能力图还是 example-* 占位符 → 不报" "无"

# ── 休眠项目的提示：有多模块产物但没落约定 ────────────────
#   这一组测的是**未激活**路径，所以不能用 base()（它写约定标题）。
#   正向三条对应三种证据，反向五条守住性质 1 和性质 2 ——
#   这个项目修过的假断链比真 bug 多，报错的那半边不值钱，
#   **不报**的那半边才是。
echo ""
echo "═══ 休眠项目的迁移提示 ═══"

nudge_base() {   # 没有 CLAUDE.md 声明块、没有 state.json 的裸项目
  rm -rf "$TMP/r"; mkdir -p "$TMP/r"; cd "$TMP/r" || exit 1
  git init -q 2>/dev/null
}
nudged() {       # 有没有出那条提示
  case "$(ctx)" in
    *"未落约定的多模块 spec 产物"*) echo yes ;;
    *)                              echo no ;;
  esac
}
nz() {           # $1=说明 $2=期望(yes/no)
  local got; got="$(nudged)"
  if [ "$got" = "$2" ]; then
    printf '  ✅ %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  ❌ %s\n     得到 [%s] 期望 [%s]\n' "$1" "$got" "$2"; FAIL=$((FAIL+1))
  fi
}

nudge_base; echo '# ch' > SPEC-channel.md
nz "正：根目录有 SPEC-<模块>.md → 提示" yes

nudge_base; echo '# m' > capability-map.md
nz "正：根目录有小写 capability-map.md → 提示" yes

nudge_base; echo '# M' > CAPABILITY-MAP.md
nz "正：根目录有大写 CAPABILITY-MAP.md → 提示" yes

nudge_base; mkdir -p tasks/a tasks/b; echo x > tasks/a/plan.md; echo x > tasks/b/plan.md
nz "正：tasks/ 下两个模块的 plan.md → 提示" yes

# ── 以下全部是反向 ──
nudge_base; echo '# 单模块' > SPEC.md
nz "反：根上只有 SPEC.md（agent-skills 合法单模块形态）→ 不提示" no

nudge_base; mkdir -p tasks/a; echo x > tasks/a/plan.md
nz "反：只有一个模块的 plan.md → 不提示" no

nudge_base
nz "反：什么产物都没有的空项目 → 不提示" no

nudge_base; echo '# ch' > SPEC-channel.md; touch .spec-guard-ignore
nz "反：有 .spec-guard-ignore → 静音" no

nudge_base; echo '# ch' > SPEC-channel.md
printf '%s\n' '<!-- BEGIN:agent-skills-convention -->' \
  '<!-- END:agent-skills-convention -->' > CLAUDE.md
nz "反：约定已激活（声明块）→ 走正常状态机，不出这条提示" no

nudge_base; echo '# ch' > SPEC-channel.md
mkdir -p .agent; echo '{"tracker":"github","activeModule":""}' > .agent/state.json
nz "反：约定已激活（state.json 零足迹）→ 不出这条提示" no

# 建议的模式要跟着远端走 —— 写死 github 会把非 GitHub 项目
# 指进一条前置检查必退 1 的路。
nudge_base; echo '# ch' > SPEC-channel.md
git remote add origin https://github.com/o/r.git 2>/dev/null
if grep -q "setup-convention github --migrate" <<<"$(ctx)"; then
  printf '  ✅ 正：远端是 GitHub → 建议 github 模式\n'; PASS=$((PASS+1))
else
  printf '  ❌ 远端是 GitHub 却没建议 github 模式\n'; FAIL=$((FAIL+1))
fi

nudge_base; echo '# ch' > SPEC-channel.md
if grep -q "setup-convention local --migrate" <<<"$(ctx)"; then
  printf '  ✅ 反：无 origin 远端 → 建议 local 模式，不指向必然失败的 github\n'; PASS=$((PASS+1))
else
  printf '  ❌ 无远端时仍建议了 github 模式\n'; FAIL=$((FAIL+1))
fi

# SSH host 别名要认成 GitHub —— 作者自己的所有仓库都是 `github-collab:`。
nudge_base; echo '# ch' > SPEC-channel.md
git remote add origin git@github-collab:o/r.git 2>/dev/null
if grep -q "setup-convention github --migrate" <<<"$(ctx)"; then
  printf '  ✅ 正：SSH host 别名 github-collab: 认成 GitHub\n'; PASS=$((PASS+1))
else
  printf '  ❌ SSH host 别名没被认成 GitHub（判据只看 host 段）\n'; FAIL=$((FAIL+1))
fi

# 反过来不能松：github 出现在**路径**里不算 GitHub。
nudge_base; echo '# ch' > SPEC-channel.md
git remote add origin https://gitlab.com/me/github-tools.git 2>/dev/null
if grep -q "setup-convention local --migrate" <<<"$(ctx)"; then
  printf '  ✅ 反：gitlab.com/me/github-tools 不算 GitHub（那是仓库名不是宿主）\n'; PASS=$((PASS+1))
else
  printf '  ❌ 路径里的 github 被误判成宿主\n'; FAIL=$((FAIL+1))
fi

# 激活之后必须还是那台状态机 —— 上面两条只验了「没出提示」，
# 空断言在这个仓库出过（0.7.20 三条），补一条正面的。
nudge_base; echo '# ch' > SPEC-channel.md
printf '%s\n' '<!-- BEGIN:agent-skills-convention -->' \
  '<!-- END:agent-skills-convention -->' > CLAUDE.md
if grep -q "当前阶段" <<<"$(ctx)"; then   # 不用管道：grep -q 命中即关，ctx 吃 SIGPIPE
  printf '  ✅ 反向断言不是空的：激活后照常注入「当前阶段」\n'; PASS=$((PASS+1))
else
  printf '  ❌ 激活后没有「当前阶段」，上面两条反向断言可能是空的\n'; FAIL=$((FAIL+1))
fi

# ── setup-convention.sh 的回归 ──
echo ""
echo "═══ setup-convention 回归 ═══"
# 注意：此时可能已 cd 到临时目录，必须用脚本开头解析的绝对路径
SETUP="$HOOKDIR/setup-convention.sh"
export CLAUDE_PLUGIN_ROOT="$PLUGDIR"

rm -rf "$TMP/s"; mkdir -p "$TMP/s"; cd "$TMP/s" || exit 1; git init -q 2>/dev/null
echo "# 原有内容" > CLAUDE.md
bash "$SETUP" local --dry-run >/dev/null 2>&1
# 用 glob 数，不用 `ls | grep`：后者对带换行/特殊字符的文件名不可靠，
# 而且 `^.git$` 里的 `.` 是通配符，`Xgit` 这种名字也会被当成 .git 排掉。
entries_except_git() {
  local n=0 e
  for e in * .[!.]* ..?*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    [ "$e" = ".git" ] && continue
    n=$((n + 1))
  done
  printf '%s' "$n"
}
if [ "$(entries_except_git)" -eq 1 ]; then
  printf '  ✅ dry-run 零写入\n'; PASS=$((PASS+1))
else
  printf '  ❌ dry-run 不该写文件\n'; FAIL=$((FAIL+1))
fi

# Codex 把约定写进 AGENTS.md；不能借用 Claude 的文件或旧标记。
rm -rf "$TMP/codex"; mkdir -p "$TMP/codex"; cd "$TMP/codex" || exit 1; git init -q 2>/dev/null
bash "$SETUP" github --host=codex >/dev/null 2>&1
if [ -f AGENTS.md ] \
   && [ "$(grep -c 'BEGIN:spec-guard-codex-convention' AGENTS.md)" -eq 1 ] \
   && [ "$(grep -c 'END:spec-guard-codex-convention' AGENTS.md)" -eq 1 ] \
   && [ ! -e CLAUDE.md ] \
   && python3 -c 'import json; json.load(open(".agent/state.json"))' 2>/dev/null; then
  printf '  ✅ Codex 写 AGENTS.md 专属块，不建 CLAUDE.md，state.json 合法\n'; PASS=$((PASS+1))
else
  printf '  ❌ Codex 安装没有使用 AGENTS.md 专属块\n'; FAIL=$((FAIL+1))
fi

# --replace 只能替换 Codex 标记内的内容。
rm -rf "$TMP/codex-replace"; mkdir -p "$TMP/codex-replace"; cd "$TMP/codex-replace" || exit 1; git init -q 2>/dev/null
printf '# 标记外开头\n' > AGENTS.md
bash "$SETUP" local --host=codex >/dev/null 2>&1
printf '\n# 标记外结尾\n' >> AGENTS.md
python3 - <<'PYEOF'
p='AGENTS.md'; s=open(p,encoding='utf-8').read()
s=s.replace('<!-- END:spec-guard-codex-convention -->', '旧 Codex 内容\n<!-- END:spec-guard-codex-convention -->')
open(p,'w',encoding='utf-8').write(s)
PYEOF
bash "$SETUP" local --host=codex --replace >/dev/null 2>&1
if grep -q '# 标记外开头' AGENTS.md && grep -q '# 标记外结尾' AGENTS.md \
   && [ "$(grep -c 'BEGIN:spec-guard-codex-convention' AGENTS.md)" -eq 1 ] \
   && [ "$(grep -c 'END:spec-guard-codex-convention' AGENTS.md)" -eq 1 ] \
   && ! grep -q '旧 Codex 内容' AGENTS.md; then
  printf '  ✅ Codex --replace 不碰 AGENTS.md 标记外内容\n'; PASS=$((PASS+1))
else
  printf '  ❌ Codex --replace 动了标记外内容或没替换块内内容\n'; FAIL=$((FAIL+1))
fi

rm -rf "$TMP/codex-dry"; mkdir -p "$TMP/codex-dry"; cd "$TMP/codex-dry" || exit 1; git init -q 2>/dev/null
bash "$SETUP" github --host=codex --dry-run >/dev/null 2>&1
if [ "$(entries_except_git)" -eq 0 ]; then
  printf '  ✅ Codex --dry-run 零写入\n'; PASS=$((PASS+1))
else
  printf '  ❌ Codex --dry-run 不该写文件\n'; FAIL=$((FAIL+1))
fi

bash "$SETUP" local --host=codex --no-instructions >/dev/null 2>&1
if [ "$?" -eq 2 ]; then
  printf '  ✅ Codex local + --no-instructions 被拒（退 2）\n'; PASS=$((PASS+1))
else
  printf '  ❌ Codex local + --no-instructions 没被拒\n'; FAIL=$((FAIL+1))
fi

rm -rf "$TMP/codex-no-claude"; mkdir -p "$TMP/codex-no-claude"; cd "$TMP/codex-no-claude" || exit 1; git init -q 2>/dev/null
bash "$SETUP" github --host=codex --no-claude-md >/dev/null 2>&1
if [ "$?" -eq 2 ] && [ ! -d .agent ]; then
  printf '  ✅ Codex + --no-claude-md 被拒（退 2 且零写入）\n'; PASS=$((PASS+1))
else
  printf '  ❌ Codex + --no-claude-md 没被拒或留下写入\n'; FAIL=$((FAIL+1))
fi

rm -rf "$TMP/codex-no-instructions"; mkdir -p "$TMP/codex-no-instructions"; cd "$TMP/codex-no-instructions" || exit 1; git init -q 2>/dev/null
bash "$SETUP" github --host=codex --no-instructions >/dev/null 2>&1
if [ -f .agent/state.json ] \
   && [ ! -e AGENTS.md ] \
   && python3 -c 'import json; json.load(open(".agent/state.json"))' 2>/dev/null; then
  printf '  ✅ Codex + --no-instructions 不写 AGENTS.md，仍建立合法 state.json\n'; PASS=$((PASS+1))
else
  printf '  ❌ Codex + --no-instructions 写了 AGENTS.md 或没建立 state.json\n'; FAIL=$((FAIL+1))
fi

cd "$TMP/s" || exit 1

bash "$SETUP" local >/dev/null 2>&1
if grep -q "原有内容" <<<"$(head -1 CLAUDE.md)"; then
  printf '  ✅ 原 CLAUDE.md 内容保留\n'; PASS=$((PASS+1))
else
  printf '  ❌ 覆盖了用户内容\n'; FAIL=$((FAIL+1))
fi

# state.json 必须是合法 JSON 且带 issueTypes 能力位（下游据此决定加不加 --type）
if python3 -c "
import json,sys
d=json.load(open('.agent/state.json'))
sys.exit(0 if isinstance(d.get('issueTypes'), bool) else 1)" 2>/dev/null; then
  printf '  ✅ state.json 合法且带 issueTypes 能力位\n'; PASS=$((PASS+1))
else
  printf '  ❌ state.json 缺 issueTypes 或不是合法 JSON\n'; FAIL=$((FAIL+1))
fi

bash "$SETUP" local >/dev/null 2>&1
if [ "$(grep -c 'BEGIN:agent-skills-convention' CLAUDE.md)" -eq 1 ]; then
  printf '  ✅ 幂等（声明块不重复）\n'; PASS=$((PASS+1))
else
  printf '  ❌ 重复写入声明块\n'; FAIL=$((FAIL+1))
fi

# local + --no-claude-md 是个装了等于没装的组合，必须被拒
rm -rf "$TMP/nl"; mkdir -p "$TMP/nl"; cd "$TMP/nl" || exit 1; git init -q 2>/dev/null
echo "# 原有" > CLAUDE.md
bash "$SETUP" local --no-claude-md >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 2 ] && [ ! -d .agent ]; then
  printf '  ✅ local + --no-claude-md 被拒（退 2 且零写入）\n'; PASS=$((PASS+1))
else
  printf '  ❌ local + --no-claude-md 没被拒（退出码 %s）\n' "$RC"; FAIL=$((FAIL+1))
fi

# ── 声明块瘦身：行数是这次改动的核心指标，钉住它 ──
GN=$(wc -l < "$PLUGDIR/templates/claude-block-github.md" | tr -d ' ')
LN=$(wc -l < "$PLUGDIR/templates/claude-block-local.md" | tr -d ' ')
if [ "$GN" -le 20 ] && [ "$LN" -le 20 ]; then
  printf '  ✅ 声明块保持精简（github %s 行 / local %s 行，上限 20）\n' "$GN" "$LN"; PASS=$((PASS+1))
else
  printf '  ❌ 声明块又胖了（github %s / local %s，上限 20）—— 细则该进 skill\n' "$GN" "$LN"; FAIL=$((FAIL+1))
fi

# ── 零 CLAUDE.md 足迹模式 ──
rm -rf "$TMP/z"; mkdir -p "$TMP/z"; cd "$TMP/z" || exit 1; git init -q 2>/dev/null
echo "# 干净项目" > CLAUDE.md
# 必须用 github 模式：local + --no-claude-md 是被禁的组合（见下）
bash "$SETUP" github --no-claude-md >/dev/null 2>&1
if [ "$(grep -c 'BEGIN:agent-skills-convention' CLAUDE.md)" -eq 0 ] && [ -f .agent/state.json ]; then
  printf '  ✅ --no-claude-md 不写声明块，但建了 state.json\n'; PASS=$((PASS+1))
else
  printf '  ❌ --no-claude-md 行为不对\n'; FAIL=$((FAIL+1))
fi
if [ -n "$(CLAUDE_PROJECT_DIR="$TMP/z" bash "$H" 2>/dev/null)" ]; then
  printf '  ✅ 零足迹下 hook 仍由 state.json 激活\n'; PASS=$((PASS+1))
else
  printf '  ❌ 零足迹下 hook 静默了 —— 这个模式等于没用\n'; FAIL=$((FAIL+1))
fi

# ── --replace 就地升级 ──
rm -rf "$TMP/u"; mkdir -p "$TMP/u"; cd "$TMP/u" || exit 1; git init -q 2>/dev/null
printf '# 我的项目\n\n标记之前的内容\n' > CLAUDE.md
bash "$SETUP" local >/dev/null 2>&1
printf '\n## 标记之后的内容\n' >> CLAUDE.md
python3 - <<'PYEOF'
p='CLAUDE.md'; s=open(p,encoding='utf-8').read()
s=s.replace('<!-- END:agent-skills-convention -->', ('旧版遗留的一大段' + chr(10)) * 30 + '<!-- END:agent-skills-convention -->')
open(p,'w',encoding='utf-8').write(s)
PYEOF
BEFORE=$(wc -l < CLAUDE.md)
bash "$SETUP" local --replace >/dev/null 2>&1
AFTER=$(wc -l < CLAUDE.md)
if [ "$AFTER" -lt "$BEFORE" ] && [ "$(grep -c '旧版遗留' CLAUDE.md)" -eq 0 ]; then
  printf '  ✅ --replace 换掉块内旧内容（%s → %s 行）\n' "$BEFORE" "$AFTER"; PASS=$((PASS+1))
else
  printf '  ❌ --replace 没清掉块内旧内容\n'; FAIL=$((FAIL+1))
fi
if grep -q "我的项目" <<<"$(head -1 CLAUDE.md)" && [ "$(grep -c '标记之后的内容' CLAUDE.md)" -eq 1 ]; then
  printf '  ✅ --replace 不碰标记外的内容\n'; PASS=$((PASS+1))
else
  printf '  ❌ --replace 动了标记外的内容 —— 这是用户自己的文档\n'; FAIL=$((FAIL+1))
fi
if [ "$(grep -c 'BEGIN:agent-skills-convention' CLAUDE.md)" -eq 1 ] \
   && [ "$(grep -c 'END:agent-skills-convention' CLAUDE.md)" -eq 1 ]; then
  printf '  ✅ --replace 后标记仍只有一对\n'; PASS=$((PASS+1))
else
  printf '  ❌ 标记重复或丢失\n'; FAIL=$((FAIL+1))
fi
BEFORE2=$(wc -l < CLAUDE.md)
bash "$SETUP" local >/dev/null 2>&1
if [ "$(wc -l < CLAUDE.md)" -eq "$BEFORE2" ]; then
  printf '  ✅ 不加 --replace 时已有块原样不动\n'; PASS=$((PASS+1))
else
  printf '  ❌ 无 --replace 却改了 CLAUDE.md\n'; FAIL=$((FAIL+1))
fi

# ── teardown-convention.sh ────────────────────────────────
# 插件里唯一的破坏性操作。0.7.9 之前它没有脚本、没有测试,而且移除不干净:
# 0.7.0 起 state.json 本身就是激活信号,只删声明块 = 切成零足迹模式。
TD="$HOOKDIR/teardown-convention.sh"

mktd() {
  rm -rf "$TMP/td"; mkdir -p "$TMP/td"; cd "$TMP/td" || exit 1; git init -q 2>/dev/null
  printf '# 我的项目\n\n构建用 npm run build。\n' > CLAUDE.md
  bash "$SETUP" github >/dev/null 2>&1
}

mktd
bash "$TD" --dry-run >/dev/null 2>&1
if [ "$(grep -c 'BEGIN:agent-skills-convention' CLAUDE.md)" -eq 1 ] && [ -f .agent/state.json ]; then
  printf '  ✅ teardown --dry-run 零写入\n'; PASS=$((PASS+1))
else
  printf '  ❌ teardown --dry-run 动了文件\n'; FAIL=$((FAIL+1))
fi

CLAUDE_PLUGIN_ROOT="$PLUGDIR" bash "$TD" >/dev/null 2>&1
if [ "$(printf '%s' "$(cat CLAUDE.md)")" = "$(printf '# 我的项目\n\n构建用 npm run build。')" ]; then
  printf '  ✅ teardown 后 CLAUDE.md 逐字回到原样\n'; PASS=$((PASS+1))
else
  printf '  ❌ teardown 后 CLAUDE.md 不是原样:\n%s\n' "$(cat CLAUDE.md)"; FAIL=$((FAIL+1))
fi

if [ -z "$(CLAUDE_PROJECT_DIR="$TMP/td" bash "$H" 2>/dev/null)" ]; then
  printf '  ✅ teardown 后 hook 真的静默\n'; PASS=$((PASS+1))
else
  printf '  ❌ teardown 后 hook 仍在注入 —— 约定没真的移除\n'; FAIL=$((FAIL+1))
fi

if [ -f .agent/state.json.disabled ] && [ ! -f .agent/state.json ]; then
  printf '  ✅ state.json 改名保留（issue 映射不丢）\n'; PASS=$((PASS+1))
else
  printf '  ❌ state.json 处理不对\n'; FAIL=$((FAIL+1))
fi

bash "$TD" >/dev/null 2>&1
if [ $? -eq 2 ]; then
  printf '  ✅ 没装过的项目退 2（幂等）\n'; PASS=$((PASS+1))
else
  printf '  ❌ 重复 teardown 应退 2\n'; FAIL=$((FAIL+1))
fi

# --keep-state:保留原名,而 hook 因此仍激活 —— 这是刻意的,要说清楚
mktd
CLAUDE_PLUGIN_ROOT="$PLUGDIR" bash "$TD" --keep-state >/dev/null 2>&1
if [ -f .agent/state.json ] && [ -n "$(CLAUDE_PROJECT_DIR="$TMP/td" bash "$H" 2>/dev/null)" ]; then
  printf '  ✅ --keep-state 保留 state.json,hook 仍激活（零足迹模式）\n'; PASS=$((PASS+1))
else
  printf '  ❌ --keep-state 行为不对\n'; FAIL=$((FAIL+1))
fi

# 两个 host 共存时，只拆目标 host；另一个声明块仍是有效激活信号，不能停用 state。
rm -rf "$TMP/td-host"; mkdir -p "$TMP/td-host"; cd "$TMP/td-host" || exit 1; git init -q 2>/dev/null
bash "$SETUP" github >/dev/null 2>&1
bash "$SETUP" github --host=codex >/dev/null 2>&1
CLAUDE_PLUGIN_ROOT="$PLUGDIR" bash "$TD" --host=codex >/dev/null 2>&1
if grep -q 'BEGIN:agent-skills-convention' CLAUDE.md \
   && ! grep -q 'BEGIN:spec-guard-codex-convention' AGENTS.md 2>/dev/null \
   && [ -f .agent/state.json ] \
   && [ ! -f .agent/state.json.disabled ]; then
  printf '  ✅ Codex teardown 只移除 Codex 块，保留 Claude 块和 state.json\n'; PASS=$((PASS+1))
else
  printf '  ❌ Codex teardown 错删其他 host 或停用了 state.json\n'; FAIL=$((FAIL+1))
fi

# ── 写操作必须钉死在项目根，不能跟着 cwd 跑 ────────────────
# Bash 的工作目录在会话里会被 cd 改掉。从子目录跑的话，setup 会把
# spec/ tasks/ .agent/ 和声明块建进**子目录**（项目里两套约定，hook 只认根上
# 那套），teardown 则会去删子目录里并不存在的块、报「什么都没做」退 2,
# 而根上的约定原封不动 —— 移除报成功却没移除。
mktd; mkdir -p src/deep
( cd src/deep && CLAUDE_PLUGIN_ROOT="$PLUGDIR" bash "$TD" >/dev/null 2>&1 )
if [ ! -d "$TMP/td/src/deep/.agent" ] \
   && [ -f "$TMP/td/.agent/state.json.disabled" ] \
   && ! grep -q "BEGIN:agent-skills-convention" "$TMP/td/CLAUDE.md" 2>/dev/null; then
  printf '  ✅ 子目录里跑 teardown 仍作用于项目根\n'; PASS=$((PASS+1))
else
  printf '  ❌ teardown 跟着 cwd 跑了 —— 根上的约定没被移除\n'; FAIL=$((FAIL+1))
fi

rm -rf "$TMP/su"; mkdir -p "$TMP/su/src/deep"; cd "$TMP/su" || exit 1; git init -q 2>/dev/null
printf '# 我的项目\n' > CLAUDE.md
( cd src/deep && bash "$SETUP" github >/dev/null 2>&1 )
if [ -d "$TMP/su/spec" ] && [ ! -d "$TMP/su/src/deep/spec" ] \
   && grep -q "BEGIN:agent-skills-convention" "$TMP/su/CLAUDE.md" 2>/dev/null \
   && [ ! -f "$TMP/su/src/deep/CLAUDE.md" ]; then
  printf '  ✅ 子目录里跑 setup 仍落在项目根\n'; PASS=$((PASS+1))
else
  printf '  ❌ setup 把约定装进了子目录（项目里会有两套）\n'; FAIL=$((FAIL+1))
fi

# 自检不能因为 CLAUDE_PLUGIN_ROOT 没设就整段跳过。
# 「实际跑一遍而不是让人相信一句话」是 0.7.9 把 teardown 改成脚本的唯一理由，
# 而它自己会退回成一句话 —— 上面所有 teardown 用例都显式设了这个变量，
# 所以三个版本没人发现。setup-convention.sh 一直有 $HERE 兜底。
mktd
case "$(bash "$TD" 2>&1)" in
  *"已验证：hook 不再注入"*)
    printf '  ✅ 不设 CLAUDE_PLUGIN_ROOT 时自检仍然真跑\n'; PASS=$((PASS+1)) ;;
  *)
    printf '  ❌ 自检被静默跳过 —— teardown 退回成「相信一句话」\n'; FAIL=$((FAIL+1)) ;;
esac

# ── setup ↔ teardown 往返:issue 映射不能丢 ─────────────────
# 0.7.9 引入 state.json.disabled 这个新状态,而 setup 不认识它 ——
# 「teardown 后改主意再 setup」会静默建一个空 state.json,真映射躺在 .disabled。
# 后果不只是丢数据:模型看到「activeModule 没有 issue」会建议 /sync-map,
# 在 GitHub 上建出一套重复 issue。
rt() {
  rm -rf "$TMP/rt"; mkdir -p "$TMP/rt"; cd "$TMP/rt" || exit 1; git init -q 2>/dev/null
  printf '# 我的项目\n' > CLAUDE.md
  bash "$SETUP" github >/dev/null 2>&1
  python3 -c "
import json
p='.agent/state.json'; d=json.load(open(p))
d['modules']={'identity':{'issue':101},'billing':{'issue':102}}
d['initiative']={'title':'x','issue':100,'map':'m'}
json.dump(d, open(p,'w'))"
  CLAUDE_PLUGIN_ROOT="$PLUGDIR" bash "$TD" >/dev/null 2>&1
}

rt
bash "$SETUP" github >/dev/null 2>&1
if python3 -c "
import json,sys
d=json.load(open('.agent/state.json'))
sys.exit(0 if len(d.get('modules') or {})==2 and (d.get('initiative') or {}).get('issue')==100 else 1)" 2>/dev/null; then
  printf '  ✅ teardown → setup 往返:issue 映射无损\n'; PASS=$((PASS+1))
else
  printf '  ❌ 往返丢了 issue 映射（下一步 /sync-map 会建重复 issue）\n'; FAIL=$((FAIL+1))
fi

rt
bash "$SETUP" local >/dev/null 2>&1
RC=$?
if [ "$RC" -ne 0 ] && [ ! -f .agent/state.json ] && [ -f .agent/state.json.disabled ]; then
  printf '  ✅ tracker 不符时拒绝恢复、也不新建（.disabled 原样保留）\n'; PASS=$((PASS+1))
else
  printf '  ❌ tracker 不符时行为不对（退出码 %s）\n' "$RC"; FAIL=$((FAIL+1))
fi

# ── --migrate：把散在根上的 spec 产物迁进 spec/ ────────────
echo ""
echo "═══ setup-convention --migrate ═══"

mig_base() {
  rm -rf "$TMP/m"; mkdir -p "$TMP/m/tasks/channel"; cd "$TMP/m" || exit 1
  git init -q 2>/dev/null
  echo '# ch'  > SPEC-channel.md
  echo '# de'  > SPEC-detection.md
  echo '# map' > capability-map.md
  echo 'see ../../SPEC-channel.md' > tasks/channel/plan.md
  git add -A >/dev/null 2>&1
  git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
}
ok_(){ printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
no_(){ printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }

# 反：不加 --migrate 一个文件都不许动
mig_base
OUT="$(bash "$SETUP" local 2>&1)"
if [ -f SPEC-channel.md ] && [ ! -f spec/channel.md ] \
   && grep -q "未迁移" <<<"${OUT}"; then
  ok_ "反：不加 --migrate → 只报告，根上的文件原样不动"
else
  no_ "反：不加 --migrate 却动了文件（或没报告）"
fi

# 正：--migrate 真迁
mig_base
bash "$SETUP" local --migrate >/dev/null 2>&1
if [ ! -f SPEC-channel.md ] && [ ! -f capability-map.md ] \
   && [ -f spec/channel.md ] && [ -f spec/detection.md ] && [ -f spec/CAPABILITY-MAP.md ]; then
  ok_ "正：--migrate → SPEC-<mod>.md 与能力图都进了 spec/"
else
  no_ "正：--migrate 没把文件迁到位"
fi

# 正：迁过来的是**原内容**，不是被模板覆盖掉的空壳。
# 这条是冲着一个具体的踩法去的：迁移和「复制能力图模板」都写
# spec/CAPABILITY-MAP.md，顺序反了就把用户写好的能力图冲掉，
# 而上一条断言（文件存在）照样绿。
if grep -q "^# map$" spec/CAPABILITY-MAP.md 2>/dev/null; then
  ok_ "正：迁过来的能力图是原内容，没被模板覆盖"
else
  no_ "正：spec/CAPABILITY-MAP.md 不是迁过来的那份 —— 被模板冲掉了"
fi

# 正：仍在引用旧路径的文件要报出来
mig_base
OUT="$(bash "$SETUP" local --migrate 2>&1)"
if grep -q "仍在引用旧路径" <<<"${OUT}" && grep -q "tasks/channel/plan.md" <<<"${OUT}"; then
  ok_ "正：报出仍在引用旧路径的文件（不自动改）"
else
  no_ "正：没报出引用旧路径的文件"
fi

# 反：目标已存在一律不覆盖，且要非零退出
mig_base; mkdir -p spec; echo '# 已有的' > spec/channel.md
bash "$SETUP" local --migrate >/dev/null 2>&1
RC=$?
if [ "$RC" -ne 0 ] && [ -f SPEC-channel.md ] && grep -q "^# 已有的$" spec/channel.md; then
  ok_ "反：目标已存在 → 不覆盖、源文件留在原地、退出码非零"
else
  no_ "反：目标已存在时覆盖了或退出码为 0（RC=${RC}）"
fi

# 反：--dry-run 下 --migrate 也不许动文件
mig_base
OUT="$(bash "$SETUP" local --migrate --dry-run 2>&1)"
if [ -f SPEC-channel.md ] && [ ! -d spec ] && grep -q "dry-run] 迁移" <<<"${OUT}"; then
  ok_ "反：--dry-run --migrate → 只打印，不动文件"
else
  no_ "反：--dry-run 下动了文件"
fi

echo ""
echo "  总计 $PASS 通过 / $FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
