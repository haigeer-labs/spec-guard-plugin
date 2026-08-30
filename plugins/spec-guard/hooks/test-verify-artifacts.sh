#!/usr/bin/env bash
# verify-artifacts.sh 回归测试
# 用法: bash plugins/spec-guard/hooks/test-verify-artifacts.sh
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V="${HOOKDIR}/verify-artifacts.sh"
[ -f "${V}" ] || { echo "找不到 ${V}"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
PASS=0; FAIL=0

# 空的骨架：启用约定 + git 仓库，其余按用例自己铺
base() {
  rm -rf "${TMP}/r"; mkdir -p "${TMP}/r/spec" "${TMP}/r/.agent"; cd "${TMP}/r" || exit 1
  git init -q 2>/dev/null
  echo "## Agent Skills 集成约定" > CLAUDE.md
}

map() {  # $@ = module ids
  { echo "# Capability Map"; echo ""
    echo "| Module id | Responsibility | Depends on |"; echo "|---|---|---|"
    for m in "$@"; do echo "| ${m} | x | — |"; done
    echo ""; echo "- [x] 已评审"; } > spec/CAPABILITY-MAP.md
}

# 跑一次，输出「通过数|警告数|失败数|退出码」
run() {
  local out rc
  out="$(CLAUDE_PROJECT_DIR="${TMP}/r" bash "${V}" 2>/dev/null)"; rc=$?
  printf '%s|%s' \
    "$(printf '%s' "${out}" | sed -n 's/.*═══ \([0-9]*\) 通过 \/ \([0-9]*\) 警告 \/ \([0-9]*\) 失败 ═══.*/\1,\2,\3/p' | tail -1)" \
    "${rc}"
}

chk() {  # $1=用例名 $2=期望 "通过,警告,失败|退出码"
  local got; got="$(run)"
  if [ "${got}" = "$2" ]; then
    printf '  ✅ %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  ❌ %s\n     得到 [%s]\n     期望 [%s]\n' "$1" "${got}" "$2"; FAIL=$((FAIL+1))
  fi
}

# 断言输出里出现/不出现某段文字
# 注意：不能写成 `bash "${V}" | grep -q`。grep -q 命中即关管道，还在输出的
# 脚本吃到 SIGPIPE(141)，pipefail 把它传出来，断言会永远判假。
has() {  # $1=用例名 $2=期望包含
  local out; out="$(CLAUDE_PROJECT_DIR="${TMP}/r" bash "${V}" 2>/dev/null)"
  case "${out}" in *"$2"*) true ;; *) false ;; esac
  if [ $? -eq 0 ]; then
    printf '  ✅ %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  ❌ %s（输出里没有 "%s"）\n' "$1" "$2"; FAIL=$((FAIL+1))
  fi
}

echo "═══ verify-artifacts 回归测试 ═══"

# ── 零误报：合规项目必须全绿 ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity; echo "## Task List" > tasks/identity/plan.md
echo '{"tracker":"none","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
chk "local 合规 → 零失败零警告" "5,0,0|0"

# ── B：文件名漂移（本脚本存在的首要理由）──
base; map identity; touch spec/user-identity.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "spec 文件名漂移被抓到" "能力图上没有的模块: user-identity"

# ── B：能力图上的模块还没写 spec，是提示不是失败 ──
base; map identity billing; touch spec/identity.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "未写的模块只提示不判失败" "还没写 spec 的模块: billing"
chk "  └ 且不计入失败" "4,0,0|0"

# ── A：模板占位符没填 ──
base; map example-a example-b; touch spec/example-a.md spec/example-b.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "模板占位符被警告" "还是模板占位符"

# ── A：module id 不是 kebab-case ──
base; map Identity_Module; touch spec/Identity_Module.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "非 kebab-case 被抓到" "不是 kebab-case"

# ── A：评审记录没勾完 ──
base; map identity; touch spec/identity.md
printf '\n- [ ] 模块边界确认\n' >> spec/CAPABILITY-MAP.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "评审未勾选被警告" "评审记录还有未勾选项"

# ── C：根目录 SPEC*.md ──
base; map identity; touch spec/identity.md SPEC.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "根目录 SPEC.md 被抓到" "根目录有 SPEC.md"

# ── C：tasks/ 缺 module 命名空间 ──
base; map identity; touch spec/identity.md
mkdir -p tasks; touch tasks/plan.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
has "tasks/ 缺命名空间被抓到" "缺 module 命名空间"

# ── C：todo.md 与 tracker 并存 ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity; touch tasks/identity/todo.md
echo '{"tracker":"github","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
has "todo.md 与 tracker 并存被抓到" "二者不能并存"
# 0.7.0 把「归档豁免」这条知识从常驻 15 行挪进了报错文案 —— 只在真报错时才花
# context。文案没了的话使用者面对违规无从下手，所以它是行为不是措辞。
has "报违规时同时给出归档豁免办法" "已归档"

# ── 归档识别：带「已归档」标记的 todo.md 不该报违规 ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity
printf '# Todo: x\n\n> ## \xe2\x9a\xa0\xef\xb8\x8f \xe5\xb7\xb2\xe5\xbd\x92\xe6\xa1\xa3 —— \xe4\xbb\xbb\xe5\x8a\xa1\xe7\xba\xa7\xe5\x85\xa8\xe9\x83\xa8\xe5\xae\x8c\xe6\x88\x90\n' > tasks/identity/todo.md
echo '{"tracker":"github","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
has "归档 todo.md 不报并存违规" "无活的 todo.md 与 tracker 并存"

# ── 归档识别：ARCHIVED 英文标记同样生效 ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity
printf '# Todo\n\n> ARCHIVED — all tasks done\n' > tasks/identity/todo.md
echo '{"tracker":"github","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
has "ARCHIVED 标记同样生效" "无活的 todo.md 与 tracker 并存"

# ── 反向：没有标记的 todo.md 仍必须报违规 ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity; printf '# Todo\n\n- [ ] 干活\n' > tasks/identity/todo.md
echo '{"tracker":"github","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
has "无标记的 todo.md 仍报违规" "二者不能并存"

# ── 归档标记只认前 10 行，正文里提到不算 ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity
{ printf '# Todo\n'; for i in $(seq 15); do echo "- [ ] t$i"; done; echo "备注：本模块稍后已归档"; } > tasks/identity/todo.md
echo '{"tracker":"github","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
has "第 10 行之后的「已归档」不算数" "二者不能并存"

# ── tasks/ 根下的归档文件不算命名空间违规 ──
base; map identity; touch spec/identity.md
mkdir -p tasks
printf '# Plan\n\n> \xe5\xb7\xb2\xe5\xbd\x92\xe6\xa1\xa3\n' > tasks/plan.md
echo '{"tracker":"github","activeModule":""}' > .agent/state.json
has "根下归档 plan.md 不报命名空间违规" "只有已归档文件（不计违规）"

# ── D：github 模式下 plan.md 里有 checkbox ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity; printf '## Task List\n- [ ] 建表\n' > tasks/identity/plan.md
echo '{"tracker":"github","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
has "plan.md 里的 checkbox 被抓到" "应是 issue 编号索引"

# ── D：local 模式下 checkbox 是正常的，不该报 ──
base; map identity; touch spec/identity.md
mkdir -p tasks/identity; printf '## Task List\n- [ ] 建表\n' > tasks/identity/plan.md
echo '{"tracker":"none","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
chk "local 模式的 checkbox 不误报" "5,0,0|0"

# ── E：无 gh / 非 github 模式必须整段跳过，不能判失败 ──
base; map identity; touch spec/identity.md
echo '{"tracker":"gitlab","activeModule":""}' > .agent/state.json
has "非 GitHub tracker 跳过 GitHub 层" "不涉及 GitHub"

# ── 降级：state.json 缺失不崩，靠 remote 推断 ──
base; map identity; touch spec/identity.md
rm -f .agent/state.json
git remote add origin https://gitlab.com/a/b.git 2>/dev/null
has "无 state.json 时按 remote 推断" "tracker=other"

# ── 未启用约定：退出码 2，不做任何判断 ──
rm -rf "${TMP}/off"; mkdir -p "${TMP}/off"; echo "# 普通项目" > "${TMP}/off/CLAUDE.md"
CLAUDE_PROJECT_DIR="${TMP}/off" bash "${V}" >/dev/null 2>&1
if [ $? -eq 2 ]; then
  printf '  ✅ 未启用约定退出码 2\n'; PASS=$((PASS+1))
else
  printf '  ❌ 未启用约定应退出 2\n'; FAIL=$((FAIL+1))
fi

# ── 模块分支：分支判定必须与 phase-guard 一致 ───────────────
# 0.6.0 改了模块分支约定,只改了 phase-guard;这里留在 task 分支时代。
# 后果:模块名自带数字时(feat/oauth2)那个 2 被当成 issue 号,
# 报「PR 正文没有 Closes #2」的假失败 —— 而 PR 里写的是正确的模块 issue。
mkdir -p "${TMP}/vbin"
cat > "${TMP}/vbin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  *"pr view"*)    printf 'Closes #5

## 变更
模块交付
' ;;
  *"issue view"*) echo "" ;;
  *sub_issues*)   echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)              echo "" ;;
esac
STUB
chmod +x "${TMP}/vbin/gh"

modrepo() {  # $1=分支名
  rm -rf "${TMP}/r"; mkdir -p "${TMP}/r/spec" "${TMP}/r/tasks/oauth2" "${TMP}/r/.agent"; cd "${TMP}/r" || exit 1
  git init -q 2>/dev/null
  echo "## Agent Skills 集成约定" > CLAUDE.md
  map oauth2; touch spec/oauth2.md
  printf '# Plan\n\n> Tasks tracked in GitHub Issues #5\n\n- #11 建表\n' > tasks/oauth2/plan.md
  echo '{"tracker":"github","activeModule":"oauth2","modules":{"oauth2":{"issue":5}}}' > .agent/state.json
  git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm i 2>/dev/null
  git checkout -qb "$1" 2>/dev/null
}

vrun() { PATH="${TMP}/vbin:$PATH" CLAUDE_PROJECT_DIR="${TMP}/r" bash "${V}" 2>/dev/null; }

modrepo feat/oauth2
OUT="$(vrun)"
case "${OUT}" in
  *"Closes #2"*) printf '  ❌ 模块分支上把模块名里的数字当成 issue 号（假失败）\n'; FAIL=$((FAIL+1)) ;;
  *"模块 PR 正文含 Closes #5"*) printf '  ✅ 模块分支比对的是模块 issue,不是分支里的数字\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 模块分支的 PR 检查没跑到\n'; FAIL=$((FAIL+1)) ;;
esac

git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: T1

Closes #11" 2>/dev/null
case "$(vrun)" in
  *"条 commit 带 closing keyword"*) printf '  ✅ 数出模块分支上带 closing keyword 的 commit\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 没统计模块分支的 closing keyword\n'; FAIL=$((FAIL+1)) ;;
esac

# 老约定的 task 分支仍按老规则(分支号 ≠ 模块 issue,PR 里没有它 → 真失败)
modrepo fix/77-something
case "$(vrun)" in
  *"PR 正文没有 Closes #77"*) printf '  ✅ task 分支仍按老规则比对分支 issue 号\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ task 分支的老路径坏了\n'; FAIL=$((FAIL+1)) ;;
esac

# ── 任务落库：sub-issue 数 ↔ plan.md 索引条数 ──────────────
# 「任务落库」此前完全没有产物校验。它一次盖住两种失败：一条都没建（任务从没落库），
# 和两边对不上（落库中途失败后重跑的残留）。
ghstub() { cat > "${TMP}/vbin/gh"; chmod +x "${TMP}/vbin/gh"; }

modrepo feat/oauth2
printf '# Plan\n\n## Task List\n> Tasks tracked in GitHub Issues #5\n\n- #11 建表\n- #12 签发\n' \
  > tasks/oauth2/plan.md
ghstub <<'STUB3'
#!/bin/bash
case "$*" in
  *sub_issues*)   echo '[]' ;;
  *"pr view"*)    echo "Closes #5" ;;
  *"issue view"*) echo "摘要" ;;
  *)              echo "" ;;
esac
STUB3
case "$(vrun)" in
  *"但 #5 下一个 sub-issue 都没有 —— 任务从没落库"*)
    printf '  ✅ plan 索引了 task 但一条 sub-issue 都没有 → 判失败\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 任务从没落库没被抓到\n'; FAIL=$((FAIL+1)) ;;
esac

# 对不上（重跑残留的形状）
ghstub <<'STUB4'
#!/bin/bash
case "$*" in
  *sub_issues*)   echo '[{"number":11,"state":"open","title":"T","assignees":[]},
                          {"number":12,"state":"open","title":"T","assignees":[]},
                          {"number":13,"state":"open","title":"T","assignees":[]}]' ;;
  *"pr view"*)    echo "Closes #5" ;;
  *"issue view"*) echo "摘要" ;;
  *)              echo "" ;;
esac
STUB4
case "$(vrun)" in
  *"plan.md 索引 2 个 task，#5 下有 3 个 sub-issue"*)
    printf '  ✅ 落库数与索引数对不上 → 警告\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 数量不一致没被抓到\n'; FAIL=$((FAIL+1)) ;;
esac

# 正向对照：数对得上就必须放行，不能变成新的误报源
ghstub <<'STUB5'
#!/bin/bash
case "$*" in
  *sub_issues*)   echo '[{"number":11,"state":"open","title":"T","assignees":[]},
                          {"number":12,"state":"open","title":"T","assignees":[]}]' ;;
  *"pr view"*)    echo "Closes #5" ;;
  *"issue view"*) echo "摘要" ;;
  *)              echo "" ;;
esac
STUB5
case "$(vrun)" in
  *"任务落库数与 plan.md 索引一致（2）"*)
    printf '  ✅ 数一致时放行（不制造新误报）\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 数一致却没放行\n'; FAIL=$((FAIL+1)) ;;
esac

# 探测失败照例 skip，不发绿灯也不判失败
ghstub <<'STUB6'
#!/bin/bash
case "$*" in
  *sub_issues*)   exit 1 ;;
  *"pr view"*)    echo "Closes #5" ;;
  *"issue view"*) echo "摘要" ;;
  *)              echo "" ;;
esac
STUB6
case "$(vrun)" in
  *"跳过任务落库比对"*)
    printf '  ✅ 读不到 sub-issue 时 skip\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 读不到 sub-issue 时没 skip\n'; FAIL=$((FAIL+1)) ;;
esac

# 还原成本节开头那个桩 —— 后面的用例依赖它（`issue view` 返回空 = 读不到正文）
ghstub <<'STUBR'
#!/bin/bash
case "$*" in
  *"pr view"*)    printf 'Closes #5\n\n## 变更\n模块交付\n' ;;
  *"issue view"*) echo "" ;;
  *sub_issues*)   echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)              echo "" ;;
esac
STUBR

# ── 探测失败不能发绿灯 ─────────────────────────────────────
# E 段段头写的是「探测失败就整段跳过，绝不误报」，但 issue 正文体量比对
# 是拿 `wc -c` 数管道输出的：gh 失败 → 0 字节 → 落进 else → 打出
# 「✅ 正文是摘要而非 spec 全文」，把「没查成」算成「查过了没问题」。
# 同段另外三处（Epic / 父 issue / PR 正文）失败时都老实 skip，只有这处不是。
modrepo feat/oauth2          # 桩里 `issue view` 返回空 = 读不到正文
case "$(vrun)" in
  *"issue #5 正文是摘要而非 spec 全文"*)
    printf '  ❌ 读不到 issue 正文却报了 ✅（没挣来的绿灯）\n'; FAIL=$((FAIL+1)) ;;
  *"读不到 issue #5 的正文"*)
    printf '  ✅ 读不到 issue 正文时 skip，不发绿灯\n'; PASS=$((PASS+1)) ;;
  *)
    printf '  ❌ issue 正文这一项整个没跑到\n'; FAIL=$((FAIL+1)) ;;
esac

# 正向对照：正文读得到、且确实是 spec 全文粘贴 → 必须仍然 warn
# （skip 不能扩大化成「什么都不查」）
modrepo feat/oauth2
python3 -c "open('spec/oauth2.md','w').write('模块规格 '*200)"
cat > "${TMP}/vbin/gh" <<'STUB2'
#!/bin/bash
case "$*" in
  *"issue view"*) cat spec/oauth2.md ;;
  *"pr view"*)    echo "Closes #5" ;;
  *sub_issues*)   echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)              echo "" ;;
esac
STUB2
chmod +x "${TMP}/vbin/gh"
case "$(vrun)" in
  *"疑似粘贴了 spec 全文"*)
    printf '  ✅ 正文确为 spec 全文时照样 warn\n'; PASS=$((PASS+1)) ;;
  *)
    printf '  ❌ spec 全文粘贴没被抓到 —— skip 扩大化了\n'; FAIL=$((FAIL+1)) ;;
esac

# ── 认不出默认分支时要说出来，不能静默 ───────────────────
# 原先 BASE 取不到 → 整个 closing keyword 比对**消失**，连一行 ⏭ 都没有。
# 同一个脚本对其余每一处探测失败都老实 skip；「没查」和「查过没问题」
# 在输出里长得一模一样，正是这个脚本存在的意义要否掉的那种。
modrepo feat/oauth2
# 注意：modrepo 收尾时已经在 feat/oauth2 上，`git branch -m X` 改的是**当前**
# 分支。要改的是基准分支，必须点名 —— 第一版就是这么写错的，两条断言全红。
BB=$(git branch --format='%(refname:short)' | grep -v '^feat/oauth2$' | head -1)
git branch -m "${BB}" trunk 2>/dev/null   # 无 remote + 非常规名 → base 无从得知
ghstub <<'STUBB'
#!/bin/bash
case "$*" in
  *"pr view"*)    echo "Closes #5" ;;
  *"issue view"*) echo "摘要" ;;
  *sub_issues*)   echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)              echo "" ;;
esac
STUBB
case "$(vrun)" in
  *"认不出默认分支"*)
    printf '  ✅ 认不出默认分支时 skip 一行，不静默\n'; PASS=$((PASS+1)) ;;
  *"本分支没有一条 commit 带 Closes"*)
    printf '  ❌ 认不出 base 却报成「一条 closing commit 都没有」（假失败）\n'; FAIL=$((FAIL+1)) ;;
  *) printf '  ❌ 认不出 base 时整段静默消失了\n'; FAIL=$((FAIL+1)) ;;
esac

# 正向：默认分支叫 develop 且有 origin/HEAD 时要真的比对，不许 skip 扩大化
modrepo feat/oauth2
BB=$(git branch --format='%(refname:short)' | grep -v '^feat/oauth2$' | head -1)
git branch -m "${BB}" develop 2>/dev/null
# 裸仓库必须用 -b 建：不然它的 HEAD 指着不存在的 main，
# `git remote set-head -a` 报 "Cannot determine remote HEAD" 并**静默失败**，
# origin/HEAD 根本没设上，这条断言就测了个空气。
rm -rf "${TMP}/o.git"; git init -q --bare -b develop "${TMP}/o.git" 2>/dev/null
git remote add origin "${TMP}/o.git" 2>/dev/null
git push -q origin develop 2>/dev/null; git remote set-head origin -a >/dev/null 2>&1
git show-ref --verify --quiet refs/remotes/origin/HEAD \
  || { printf '  ❌ 脚手架没设上 origin/HEAD，下面这条测的是空气\n'; FAIL=$((FAIL+1)); }
git checkout -q feat/oauth2 2>/dev/null
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: T1

Closes #11" 2>/dev/null
case "$(vrun)" in
  *"认不出默认分支"*)
    printf '  ❌ 有 origin/HEAD 指着 develop 却说认不出 —— skip 扩大化了\n'; FAIL=$((FAIL+1)) ;;
  *"条 commit 带 closing keyword"*)
    printf '  ✅ 默认分支 develop 时照样比对得出来\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ develop 仓库上 closing keyword 比对没跑到\n'; FAIL=$((FAIL+1)) ;;
esac

# ── Epic 正文也要体检（issue #3）─────────────────────────
# 此前只查模块 issue 的正文，而**唯一一处流程明确指示粘贴全文的地方恰恰是
# Epic**：操作一步骤 2 原来写的就是 `--body-file spec/CAPABILITY-MAP.md`，
# 同一节末尾十几行后又写「不要把 spec 全文复制进 issue 正文」。
# 规则和判据差了一个 issue 的距离，检查器盖不到发布方自己写的那条错。
epicrepo() {  # 带 initiative.issue 的仓库；modrepo 那份没有，EPIC 为空整段跳过
  modrepo feat/oauth2
  echo '{"tracker":"github","activeModule":"oauth2","initiative":{"issue":1},"modules":{"oauth2":{"issue":5}}}' > .agent/state.json
}

epicrepo
ghstub <<'STUBE1'
#!/bin/bash
case "$*" in
  *"issue view 1"*) cat spec/CAPABILITY-MAP.md ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)     echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                echo "" ;;
esac
STUBE1
case "$(vrun)" in
  *"疑似灌了能力图全文"*)
    printf '  ✅ Epic 正文是能力图全文时 warn\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ Epic 正文粘贴全文没被抓到\n'; FAIL=$((FAIL+1)) ;;
esac

# 反向：摘要不能被报成粘贴（误报比漏报危害大）
epicrepo
ghstub <<'STUBE2'
#!/bin/bash
case "$*" in
  *"issue view 1"*) echo '能力图: `spec/CAPABILITY-MAP.md`' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)     echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                echo "" ;;
esac
STUBE2
case "$(vrun)" in
  *"疑似灌了能力图全文"*)
    printf '  ❌ Epic 摘要被误报成粘贴全文\n'; FAIL=$((FAIL+1)) ;;
  *"Epic #1 正文是摘要而非能力图全文"*)
    printf '  ✅ Epic 正文是摘要时放行\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ Epic 正文这一项没跑到\n'; FAIL=$((FAIL+1)) ;;
esac

# 反向：读不到 Epic 正文时必须 skip —— 模块那处发过一次没挣来的绿灯，
# 新加的这处不能重蹈。gh 失败 → 0 字节 → 落进 else → 报 ✅。
epicrepo
ghstub <<'STUBE3'
#!/bin/bash
case "$*" in
  *"issue view 1"*) echo "" ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)     echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                echo "" ;;
esac
STUBE3
case "$(vrun)" in
  *"Epic #1 正文是摘要而非能力图全文"*)
    printf '  ❌ 读不到 Epic 正文却报了 ✅（没挣来的绿灯）\n'; FAIL=$((FAIL+1)) ;;
  *"读不到 Epic #1 的正文"*)
    printf '  ✅ 读不到 Epic 正文时 skip，不发绿灯\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ Epic 正文这一项整个没跑到\n'; FAIL=$((FAIL+1)) ;;
esac

# ── 重复的 Epic（0.7.18 起挂在已知限制里）────────────────
# 操作一中途失败后重跑会在 GitHub 上留下第二个 Epic，而**已有的每一项检查
# 问的都是 state.json 记着的那一个** —— 没被记下的那个谁都看不见。
# 判据只认「与记录在案的那个 Epic 标题逐字相同的 open issue」：
# 重跑用的是同一份能力图，标题必然相同；不同名的两个 initiative 同时开着
# 是正常的，报了就是假断链（A1）。
epicrepo
ghstub <<'STUBD1'
#!/bin/bash
case "$*" in
  *"issue list"*)   echo '[{"number":1,"title":"Initiative: 支付平台"},{"number":40,"title":"Initiative: 支付平台"},{"number":5,"title":"oauth2"}]' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)     echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                echo "" ;;
esac
STUBD1
case "$(vrun)" in
  *"还有同名的 open issue: #40"*)
    printf '  ✅ 重跑留下的第二个 Epic 被抓到\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 重复的 Epic 没被抓到\n'; FAIL=$((FAIL+1)) ;;
esac

# 反：同名的只有它自己 → 放行
epicrepo
ghstub <<'STUBD2'
#!/bin/bash
case "$*" in
  *"issue list"*)   echo '[{"number":1,"title":"Initiative: 支付平台"},{"number":5,"title":"oauth2"}]' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)     echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                echo "" ;;
esac
STUBD2
case "$(vrun)" in
  *"还有同名的 open issue"*)
    printf '  ❌ 只有自己一个却报了重复（假失败）\n'; FAIL=$((FAIL+1)) ;;
  *"没有与 Epic #1 同名的其他 open issue"*)
    printf '  ✅ 无重复时放行\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 重复 Epic 这一项没跑到\n'; FAIL=$((FAIL+1)) ;;
esac

# 反：另一个**不同名**的 initiative 同时开着 —— 这是正常的，不许报
epicrepo
ghstub <<'STUBD3'
#!/bin/bash
case "$*" in
  *"issue list"*)   echo '[{"number":1,"title":"Initiative: 支付平台"},{"number":60,"title":"Initiative: 风控"}]' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)     echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                echo "" ;;
esac
STUBD3
case "$(vrun)" in
  *"还有同名的 open issue"*)
    printf '  ❌ 不同名的两个 initiative 被报成重复（假失败）\n'; FAIL=$((FAIL+1)) ;;
  *"没有与 Epic #1 同名的其他 open issue"*)
    printf '  ✅ 不同名的 initiative 同时开着不报\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 重复 Epic 这一项没跑到\n'; FAIL=$((FAIL+1)) ;;
esac

# 反：记着的 Epic 已关闭（不在 open 列表里）→ skip，不猜
epicrepo
ghstub <<'STUBD4'
#!/bin/bash
case "$*" in
  *"issue list"*)   echo '[{"number":60,"title":"Initiative: 风控"}]' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)     echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                echo "" ;;
esac
STUBD4
case "$(vrun)" in
  *"不在 open issue 列表里"*)
    printf '  ✅ 记着的 Epic 已关闭时 skip，不猜\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 记着的 Epic 不在 open 列表时没 skip\n'; FAIL=$((FAIL+1)) ;;
esac

# 反：读不到 open issue 列表时必须 skip，不发绿灯（同段其余每一处都是这么做的）
epicrepo
ghstub <<'STUBD5'
#!/bin/bash
case "$*" in
  *"issue list"*)   exit 1 ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)     echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                echo "" ;;
esac
STUBD5
case "$(vrun)" in
  *"没有与 Epic #1 同名的其他 open issue"*)
    printf '  ❌ 读不到 issue 列表却报了 ✅（没挣来的绿灯）\n'; FAIL=$((FAIL+1)) ;;
  *"读不到 open issue 列表"*)
    printf '  ✅ 读不到 issue 列表时 skip，不发绿灯\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 重复 Epic 这一项整个没跑到\n'; FAIL=$((FAIL+1)) ;;
esac

# issue list 的 201 条窗口意味着列表被截断。即便记录在案的 Epic 在窗口内，
# 也不能把窗口内未命中同名项说成全局没有。
epicrepo
ghstub <<'STUBD8'
#!/bin/bash
case "${*}" in
  *"issue list"*)   python3 -c 'import json; print(json.dumps([{"number":1,"title":"Initiative: 支付平台"}] + [{"number":n,"title":"别的 issue"} for n in range(2, 202)]))' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)      echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                 echo "" ;;
esac
STUBD8
case "$(vrun)" in
  *"没有与 Epic #1 同名的其他 open issue"*)
    printf '  ❌ 201 条截断列表里没找到同名项却报了 ✅\n'; FAIL=$((FAIL+1)) ;;
  *"不代表通过"*)
    printf '  ✅ 201 条截断列表里没找到同名项 → skip，不报 ✅\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 201 条截断列表没有明确 skip\n'; FAIL=$((FAIL+1)) ;;
esac

# 未截断的 200 条以内列表仍可给出「没有同名项」的正常结论。
epicrepo
ghstub <<'STUBD9'
#!/bin/bash
case "${*}" in
  *"issue list"*)   python3 -c 'import json; print(json.dumps([{"number":1,"title":"Initiative: 支付平台"}] + [{"number":n,"title":"别的 issue"} for n in range(2, 201)]))' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)      echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                 echo "" ;;
esac
STUBD9
case "$(vrun)" in
  *"没有与 Epic #1 同名的其他 open issue"*)
    printf '  ✅ 200 条以内无同名项仍报 ✅\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 200 条以内无同名项被错误 skip\n'; FAIL=$((FAIL+1)) ;;
esac

# 判据写的是标题逐字相同；空白数量不同不是重复。
epicrepo
ghstub <<'STUBD10'
#!/bin/bash
case "${*}" in
  *"issue list"*)   echo '[{"number":1,"title":"Initiative: 支付 平台"},{"number":40,"title":"Initiative: 支付  平台"}]' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)      echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                 echo "" ;;
esac
STUBD10
case "$(vrun)" in
  *"还有同名的 open issue"*)
    printf '  ❌ 标题只差空白数量仍被报成重复\n'; FAIL=$((FAIL+1)) ;;
  *"没有与 Epic #1 同名的其他 open issue"*)
    printf '  ✅ 标题只差空白数量不报重复\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 空白差异的重复 Epic 判据没跑到\n'; FAIL=$((FAIL+1)) ;;
esac

# 反向：逐字相同仍必须判为重复，防止把判据收窄过头。
epicrepo
ghstub <<'STUBD11'
#!/bin/bash
case "${*}" in
  *"issue list"*)   echo '[{"number":1,"title":"Initiative: 支付平台"},{"number":40,"title":"Initiative: 支付平台"}]' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)      echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                 echo "" ;;
esac
STUBD11
case "$(vrun)" in
  *"还有同名的 open issue: #40"*)
    printf '  ✅ 标题逐字相同仍报重复\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 标题逐字相同的重复 Epic 没被抓到\n'; FAIL=$((FAIL+1)) ;;
esac

# state.json 没有 initiative.issue，而 GitHub 上已经有像 Epic 的 open issue ——
# 这是「重跑会再建一套」的前夜。只 warn：那个 issue 也可能跟本插件无关。
modrepo feat/oauth2          # 这份 state.json 没有 initiative
ghstub <<'STUBD6'
#!/bin/bash
case "$*" in
  *"issue list"*)   echo '[{"number":40,"title":"Initiative: 支付平台"},{"number":5,"title":"oauth2"}]' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)     echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                echo "" ;;
esac
STUBD6
case "$(vrun)" in
  *"但 GitHub 上已有标题像 Epic 的 open issue #40"*)
    printf '  ✅ state.json 空着而 GitHub 上已有 Epic → warn\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 「建到一半」的残留没被提示\n'; FAIL=$((FAIL+1)) ;;
esac

# 反：没有 initiative.issue、GitHub 上也没有像 Epic 的 issue → 不许报
modrepo feat/oauth2
ghstub <<'STUBD7'
#!/bin/bash
case "$*" in
  *"issue list"*)   echo '[{"number":5,"title":"oauth2"}]' ;;
  *"issue view"*)   echo "摘要" ;;
  *"pr view"*)      echo "Closes #5" ;;
  *sub_issues*)     echo '[{"number":11,"state":"open","title":"T1","assignees":[]}]' ;;
  *)                echo "" ;;
esac
STUBD7
case "$(vrun)" in
  *"标题像 Epic 的 open issue"*)
    printf '  ❌ 没有 Epic 时也报了（假断链）\n'; FAIL=$((FAIL+1)) ;;
  *"GitHub 上没有孤儿 Epic"*)
    printf '  ✅ 没有孤儿 Epic 时放行\n'; PASS=$((PASS+1)) ;;
  *) printf '  ❌ 重复 Epic 这一项没跑到\n'; FAIL=$((FAIL+1)) ;;
esac

# ── 归档识别不能被大文件搞挂（与 phase-guard 同一条判据）──
# is_archived 两边是同一份实现，`head -10 | grep -q` 的 SIGPIPE 也是同一个。
# 本仓的规矩：两个 hook 共用的判据要在两边都加用例。
base; map identity; touch spec/identity.md
mkdir -p tasks/identity; echo "## Task List" > tasks/identity/plan.md
printf '> Tasks tracked in GitHub\n' >> tasks/identity/plan.md
echo '{"tracker":"github","activeModule":"identity","modules":{"identity":{}}}' > .agent/state.json
python3 -c "open('tasks/identity/todo.md','w').write('已归档 '+'y'*400000+chr(10))"
case "$(CLAUDE_PROJECT_DIR="${TMP}/r" bash "${V}" 2>/dev/null)" in
  *"二者不能并存"*) printf '  ❌ 前10行超大的已归档 todo.md 被误报成并存\n'; FAIL=$((FAIL+1)) ;;
  *)                printf '  ✅ 前10行超大的已归档 todo.md 仍被豁免\n'; PASS=$((PASS+1)) ;;
esac

python3 -c "open('tasks/identity/todo.md','w').write('活的清单 '+'y'*400000+chr(10))"
case "$(CLAUDE_PROJECT_DIR="${TMP}/r" bash "${V}" 2>/dev/null)" in
  *"二者不能并存"*) printf '  ✅ 同样大但没归档声明的 todo.md 照报并存\n'; PASS=$((PASS+1)) ;;
  *)                printf '  ❌ 大文件把并存检测整个吞掉了\n'; FAIL=$((FAIL+1)) ;;
esac

# ── 零 CLAUDE.md 足迹：只有 .agent/state.json 也要生效（0.7.0）──
# phase-guard 那边有同名用例，verify-artifacts 这边一直漏着 ——
# 两个 hook 同时改的激活判据，只测了一个。
rm -rf "${TMP}/zf"; mkdir -p "${TMP}/zf/.agent"
echo "# 普通项目（没有约定标题）" > "${TMP}/zf/CLAUDE.md"
echo '{"tracker":"none","activeModule":""}' > "${TMP}/zf/.agent/state.json"
CLAUDE_PROJECT_DIR="${TMP}/zf" bash "${V}" >/dev/null 2>&1
if [ $? -ne 2 ]; then
  printf '  ✅ 零足迹：只有 state.json 也生效\n'; PASS=$((PASS+1))
else
  printf '  ❌ 零足迹下退出 2 —— --no-claude-md 装出来的项目校验不了\n'; FAIL=$((FAIL+1))
fi

# 反向：两个信号都没有，仍然必须退 2（上面那条不能把闸门整个拆了）
rm -rf "${TMP}/zn"; mkdir -p "${TMP}/zn"; echo "# 普通项目" > "${TMP}/zn/CLAUDE.md"
CLAUDE_PROJECT_DIR="${TMP}/zn" bash "${V}" >/dev/null 2>&1
if [ $? -eq 2 ]; then
  printf '  ✅ 两个信号都没有仍退 2\n'; PASS=$((PASS+1))
else
  printf '  ❌ 无信号时不该生效 —— 会污染无关项目\n'; FAIL=$((FAIL+1))
fi

# ── A2. 能力图 ↔ 投影的指纹 ────────────────────────────────
#   **两个 hook 共用的判据必须在两边都有用例。** 0.7.0 同时改了两边的激活
#   判据却只给 phase-guard 加了测试，verify-artifacts 漏了三个版本。
#   这一组和 test-phase-guard.sh 里那组是同一份判据的两个宿主。
hasnt() {  # $1=用例名 $2=不该出现的文字
  local out; out="$(CLAUDE_PROJECT_DIR="${TMP}/r" bash "${V}" 2>/dev/null)"
  case "${out}" in
    *"$2"*) printf '  ❌ %s（输出里不该有 "%s"）\n' "$1" "$2"; FAIL=$((FAIL+1)) ;;
    *)      printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)) ;;
  esac
}

DIGEST="${HOOKDIR}/spec-digest.py"

dmap() {  # $1=目标段（- 表示没有这一节） 余下=「id|职责」
  local goal="$1"; shift
  { echo "# Capability Map"; echo ""
    if [ "${goal}" != "-" ]; then echo "## 目标"; echo ""; echo "${goal}"; echo ""; fi
    echo "## 模块"; echo ""
    echo "| Module id | Responsibility | Depends on |"; echo "|---|---|---|"
    local r
    for r in "$@"; do printf '| %s | %s | — |\n' "${r%%|*}" "${r#*|}"; done
    echo ""; echo "- [x] 已评审"; } > spec/CAPABILITY-MAP.md
}

dsynced() {  # 用 spec-digest.py 自己算出「完全同步」的 state.json
  python3 - "${DIGEST}" spec/CAPABILITY-MAP.md > .agent/state.json <<'PY'
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

G='给小店主一个能自己上架、自己收款的后台。'

base; dmap "${G}" 'identity|登录注册' 'catalog|商品上架'; dsynced
has  "指纹：同步态报「都已落成 issue」" "能力图的 2 个模块都已落成 issue"
has  "指纹：同步态报「目标段一致」"     "Epic 正文摘要与能力图目标段一致"

base; dmap "${G}" 'identity|登录注册' 'catalog|商品上架'; dsynced
dmap "${G}" 'identity|登录注册' 'catalog|商品上架' 'payments|收款'
has  "指纹：加了模块 → 报出是哪个" "其中 1 个没落成 issue: payments"

base; dmap "${G}" 'identity|登录注册' 'catalog|商品上架'; dsynced
dmap '改成给连锁店用。' 'identity|登录注册' 'catalog|商品上架'
has  "指纹：改目标段 → 报 Epic 正文摘要过期" "「## 目标」段改过"

base; dmap "${G}" 'identity|登录注册' 'catalog|商品上架'; dsynced
dmap "${G}" 'identity|登录注册、会话、找回密码' 'catalog|商品上架'
has  "指纹：改职责 → 报对应 issue 正文摘要过期" "identity 的职责描述改过"

# 反方向在这一层只 warn 不 bad —— 手动跑时人在旁边，能自己判断弃用还是手滑；
# phase-guard 每轮自动跑时问不了人，所以那边整个不报。
base; dmap "${G}" 'identity|登录注册' 'catalog|商品上架'; dsynced
dmap "${G}" 'identity|登录注册'
has  "指纹：能力图删了行 → warn 而不是 bad（手动跑时人能判断）" "但能力图里已经没有这一行"

# ── 反向用例 ──
base; dmap '改成给连锁店用。' 'identity|登录注册、会话、找回密码' 'catalog|商品上架'
echo '{"tracker":"github","activeModule":"identity","initiative":{"issue":100},"modules":{"identity":{"issue":101},"catalog":{"issue":102}}}' > .agent/state.json
hasnt "反：老 state.json 没存指纹 → 不报目标段过期" "「## 目标」段改过"
hasnt "反：老 state.json 没存指纹 → 不报职责过期"   "的职责描述改过"

base; dmap "${G}" 'identity|登录注册' 'catalog|商品上架' 'payments|收款'
echo '{"tracker":"none","activeModule":"identity","modules":{}}' > .agent/state.json
has   "反：tracker=none → 整段 skip，不发绿灯也不报" "指纹只由 /sync-map 写"

base; dmap "${G}" 'identity|登录注册' 'catalog|商品上架' 'payments|收款'
echo '{"tracker":"github","activeModule":"identity","modules":{}}' > .agent/state.json
has   "反：一个都还没落 → skip（Phase 0 中间态）" "Phase 0 尚未同步"

base; dmap "${G}" 'example-a|...' 'example-b|...'
echo '{"tracker":"github","activeModule":"identity","modules":{"example-a":{"issue":101}}}' > .agent/state.json
has   "反：还是 example-* 占位符 → skip" "example-* 占位符"

base; dmap "${G}" 'identity|登录注册' 'catalog|商品上架'
printf '{{{ not json' > .agent/state.json
hasnt "反：state.json 坏掉 → 不报任何指纹分歧" "没落成 issue"


# ── 目录不存在不崩 ──
CLAUDE_PROJECT_DIR="${TMP}/nope" bash "${V}" >/dev/null 2>&1
if [ $? -eq 1 ]; then
  printf '  ✅ 目录不存在时干净报错\n'; PASS=$((PASS+1))
else
  printf '  ❌ 目录不存在时应退出 1\n'; FAIL=$((FAIL+1))
fi

# ── 远端判定：与 phase-guard 共用的判据，两边都要有用例 ────
echo ""
echo "═══ 远端 host 判定（与 phase-guard 共用）═══"
base; map identity
echo '{"tracker":"","modules":{},"activeModule":""}' > .agent/state.json
git remote add origin git@github-collab:o/r.git 2>/dev/null
has "正：SSH host 别名 github-collab: 认成 github" "tracker=github"

base; map identity
echo '{"tracker":"","modules":{},"activeModule":""}' > .agent/state.json
git remote add origin https://gitlab.com/me/github-tools.git 2>/dev/null
has "反：路径里的 github 不算宿主 → tracker=other" "tracker=other"

echo ""
echo "  总计 ${PASS} 通过 / ${FAIL} 失败"
[ "${FAIL}" -eq 0 ] || exit 1
