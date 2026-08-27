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
  rm -rf "$TMP/r"; mkdir -p "$TMP/r"; cd "$TMP/r"
  git init -q 2>/dev/null
  echo "## Agent Skills 集成约定" > CLAUDE.md
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

echo "═══ phase-guard 回归测试 ═══"

base
chk "空仓库" "IDLE|断链0"

base; mkdir -p spec; touch spec/CAPABILITY-MAP.md
chk "只有能力图" "MAP_ONLY|断链1"

base; mkdir -p spec; touch spec/CAPABILITY-MAP.md spec/a.md
chk "spec无issue(无remote→本地)" "SPECED (本地模式)|断链1"

base; touch SPEC.md; mkdir -p spec; touch spec/a.md
chk "根目录SPEC(无remote→本地)" "SPECED (本地模式)|断链2"

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
if CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null | grep -q "activeModule=\[x\]"; then
  printf '  ✅ 断链文案指名 activeModule\n'; PASS=$((PASS+1))
else
  printf '  ❌ 断链文案未指名 activeModule\n'; FAIL=$((FAIL+1))
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

# 反向用例：真的在错误分支上（不是模块分支、也没 issue 号）仍然要报
mod_repo
chk "已认领却停在默认分支 → 真断链照报" "TASK_CLAIMED|断链1"

# 反向用例：module id 是单字母时，"master" 不能被当成模块分支
base; mkdir -p spec tasks/a .agent; touch spec/a.md tasks/a/plan.md
echo '{"tracker":"github","activeModule":"a","modules":{"a":{"issue":9}}}' > .agent/state.json
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm p 2>/dev/null
git checkout -qb master 2>/dev/null || git checkout -q master 2>/dev/null
chk "module id=a 时 master 不算模块分支（子串陷阱）" "TASK_CLAIMED|断链1"

export PATH="$OLDPATH"

# ── 零足迹模式要把触发指令补回来 ──
# 实测依据：evals 的 B 组(= 这个模式)hook 正常激活但模型全程没加载 skill。
# hook 注入的是状态，而让 skill 被加载的是那句指令 —— 少了它这个模式就是陷阱。
ctx() {
  CLAUDE_PROJECT_DIR="$TMP/r" bash "$H" 2>/dev/null | python3 -c '
import sys, json
try: print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception: print("")'
}

rm -rf "$TMP/r"; mkdir -p "$TMP/r/.agent"; cd "$TMP/r"; git init -q 2>/dev/null
echo "# 普通项目（没有约定标题）" > CLAUDE.md
echo '{"tracker":"none","activeModule":""}' > .agent/state.json
if case "$(ctx)" in *"spec-github-bridge"*) true ;; *) false ;; esac; then
  printf '  ✅ 零足迹：注入「先加载 spec-github-bridge」\n'; PASS=$((PASS+1))
else
  printf '  ❌ 零足迹下没注入触发指令 —— --no-claude-md 会退化成没有约定\n'; FAIL=$((FAIL+1))
fi

base   # 有声明块
if case "$(ctx)" in *"零足迹模式"*) false ;; *) true ;; esac; then
  printf '  ✅ 有声明块时一个字都不多\n'; PASS=$((PASS+1))
else
  printf '  ❌ 有声明块的项目也被塞了零足迹提示（白花 context）\n'; FAIL=$((FAIL+1))
fi

# 本地模式零足迹：不能指向 spec-github-bridge —— 那个 skill 全篇是 gh issue,
# 对 tracker=none 的项目毫无意义,指过去只会让它去建根本不存在的 issue
rm -rf "$TMP/r"; mkdir -p "$TMP/r/.agent"; cd "$TMP/r"; git init -q 2>/dev/null
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

# ── setup-convention.sh 的回归 ──
echo ""
echo "═══ setup-convention 回归 ═══"
# 注意：此时可能已 cd 到临时目录，必须用脚本开头解析的绝对路径
SETUP="$HOOKDIR/setup-convention.sh"
export CLAUDE_PLUGIN_ROOT="$PLUGDIR"

rm -rf "$TMP/s"; mkdir -p "$TMP/s"; cd "$TMP/s"; git init -q 2>/dev/null
echo "# 原有内容" > CLAUDE.md
bash "$SETUP" local --dry-run >/dev/null 2>&1
if [ "$(ls -A | grep -vc '^.git$')" -eq 1 ]; then
  printf '  ✅ dry-run 零写入\n'; PASS=$((PASS+1))
else
  printf '  ❌ dry-run 不该写文件\n'; FAIL=$((FAIL+1))
fi

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
rm -rf "$TMP/nl"; mkdir -p "$TMP/nl"; cd "$TMP/nl"; git init -q 2>/dev/null
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
rm -rf "$TMP/z"; mkdir -p "$TMP/z"; cd "$TMP/z"; git init -q 2>/dev/null
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
rm -rf "$TMP/u"; mkdir -p "$TMP/u"; cd "$TMP/u"; git init -q 2>/dev/null
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

echo ""
echo "  总计 $PASS 通过 / $FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
