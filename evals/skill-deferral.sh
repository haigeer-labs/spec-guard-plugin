#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# skill-deferral —— 验证 0.7.0 那次瘦身赖以成立的那个假设
#
#   「15 行的声明块 + 一句触发指令，模型真的会去加载 spec-github-bridge」
#
# 如果不会，那次瘦身就等于把细则删了。这个假设此前**一次都没验过** ——
# 本仓的规矩是「标了『没实测』之后就该去测」。
#
# 做法：两个只差一个声明块的脚手架项目，同一句话，headless 跑，
#       从 stream-json 里看有没有 Skill(spec-github-bridge) 的 tool_use。
#
# ⚠️ 会真的调模型、花 token。**不接进 validate.sh**，按需手动跑。
#
# 用法:
#   bash evals/skill-deferral.sh              # 建脚手架 + 跑两组 + 判分
#   bash evals/skill-deferral.sh --scaffold-only   # 只建脚手架，不调模型（免费自检）
#   bash evals/skill-deferral.sh --grade-only <目录> # 只对已有 transcript 判分
#
# 为什么不用 `claude plugin eval`：它是 early access，本账号未开通（2026-08-27）。
# 开通之后应该迁过去 —— 那才是第一方格式。
# ─────────────────────────────────────────────────────────────
set -uo pipefail

MODE=run
[ "${1:-}" = "--scaffold-only" ] && MODE=scaffold
[ "${1:-}" = "--grade-only" ] && { MODE=grade; DIR="${2:?--grade-only 要给目录}"; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUG="$(cd "$HERE/.." && pwd)/plugins/spec-guard"
PROMPT="帮我开始做 identity 模块的下一个任务"
WORK="${TMPDIR:-/tmp}/spec-guard-eval-$$"

grade() {  # $1=jsonl  $2=组名
  python3 - "$1" "$2" <<'PY'
import sys, json
path, arm = sys.argv[1], sys.argv[2]
tools, skills = [], []
for line in open(path, encoding='utf-8'):
    try: e = json.loads(line)
    except Exception: continue
    if not isinstance(e, dict) or e.get('type') != 'assistant': continue
    msg = e.get('message')
    if not isinstance(msg, dict): continue
    for c in msg.get('content') or []:
        if not isinstance(c, dict) or c.get('type') != 'tool_use': continue
        tools.append(str(c.get('name')))
        if c.get('name') == 'Skill':
            inp = c.get('input')
            skills.append((inp or {}).get('skill') if isinstance(inp, dict) else None)
# skill 名带插件命名空间（spec-guard:spec-github-bridge），按末段比对。
# 第一版判据写死了裸名，把一次成功判成了失败 —— 防线本身也要被测试。
hit = any(s and s.split(':')[-1] == 'spec-github-bridge' for s in skills)
print(f"  [{arm}] 工具 {len(tools)} 次 · skill={[s for s in skills if s] or '无'}")
if hit:
    i = next(k for k, t in enumerate(tools) if t == 'Skill')
    print(f"  [{arm}] ✅ 加载了 spec-github-bridge（第 {i+1} 个工具调用）")
else:
    print(f"  [{arm}] ❌ 没加载 spec-github-bridge")
sys.exit(0 if hit else 1)
PY
}

if [ "$MODE" = grade ]; then
  grade "$DIR/armA.jsonl" "A 有声明块"; A=$?
  grade "$DIR/armB.jsonl" "B 无声明块"; B=$?
  [ "$A" -eq 0 ] && [ "$B" -ne 0 ] && { echo "  ✅ 结论成立：声明块是 skill 被加载的原因"; exit 0; }
  echo "  ⚠️  结论不成立（A 应加载、B 应不加载）"; exit 1
fi

mk() {  # $1=目录 $2=with|without
  rm -rf "$1"; mkdir -p "$1/spec" "$1/tasks/identity" "$1/.agent"
  ( cd "$1" && git init -q )
  printf '# CLAUDE.md\n\n本项目是一个身份服务。构建用 `npm run build`，测试用 `npm test`。\n' > "$1/CLAUDE.md"
  if [ "$2" = with ]; then
    {
      echo ""
      echo "<!-- BEGIN:agent-skills-convention -->"
      cat "$PLUG/templates/claude-block-github.md"
      echo "<!-- END:agent-skills-convention -->"
    } >> "$1/CLAUDE.md"
  fi
  printf '# 能力图\n\n| module | build order |\n|---|---|\n| identity | 1 |\n' > "$1/spec/CAPABILITY-MAP.md"
  printf '# identity\n\n验收：用户能注册、登录、登出。\n' > "$1/spec/identity.md"
  printf '# Plan: identity\n\n> Tasks tracked in GitHub Issues #101\n\n## Task List\n- #110 建立 session 表\n- #111 实现 token 签发\n' > "$1/tasks/identity/plan.md"
  echo '{"tracker":"github","issueTypes":false,"modules":{"identity":{"issue":101}},"activeModule":"identity"}' > "$1/.agent/state.json"
  ( cd "$1" && git add -A >/dev/null && git -c user.email=t@t -c user.name=t commit -qm init )
}

mkdir -p "$WORK"
mk "$WORK/armA" with
mk "$WORK/armB" without
echo "  脚手架: $WORK"
echo "  armA CLAUDE.md $(wc -l < "$WORK/armA/CLAUDE.md" | tr -d ' ') 行 · armB $(wc -l < "$WORK/armB/CLAUDE.md" | tr -d ' ') 行"

# 自检：A 组的 hook 必须认得出，否则整个评测测的是空气
HOOKOUT=$(CLAUDE_PROJECT_DIR="$WORK/armA" CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUG/hooks/phase-guard.sh" 2>/dev/null)
if [ -z "$HOOKOUT" ]; then
  echo "  ❌ A 组上 hook 静默 —— 脚手架没激活约定，评测无意义"; exit 1
fi
echo "  ✅ A 组 hook 已激活"
if [ -z "$(CLAUDE_PROJECT_DIR="$WORK/armB" CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUG/hooks/phase-guard.sh" 2>/dev/null)" ]; then
  echo "  ⚠️  B 组 hook 也静默 —— 注意 B 组有 .agent/state.json，0.7.0 起它本身就是激活信号"
else
  echo "  ℹ  B 组 hook 同样激活（靠 .agent/state.json）—— 差异因此只来自声明块本身，这正是要的"
fi

[ "$MODE" = scaffold ] && { echo "  --scaffold-only：到此为止，未调用模型"; exit 0; }

for arm in A B; do
  echo "  跑 $arm 组…"
  ( cd "$WORK/arm$arm" && claude -p "$PROMPT" \
      --output-format stream-json --verbose --max-turns 8 \
      --allowedTools Read Glob Grep Skill ) > "$WORK/arm$arm.jsonl" 2>/dev/null
done

grade "$WORK/armA.jsonl" "A 有声明块"; A=$?
grade "$WORK/armB.jsonl" "B 无声明块"; B=$?
if [ "$A" -eq 0 ] && [ "$B" -ne 0 ]; then
  echo "  ✅ 结论成立：声明块是 skill 被加载的原因"; exit 0
fi
echo "  ⚠️  结论不成立（期望 A 加载、B 不加载）"; exit 1
