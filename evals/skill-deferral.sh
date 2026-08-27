#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# skill-deferral —— 验证 0.7.0 那次瘦身赖以成立的那个假设
#
#   「模型真的会去加载 spec-github-bridge」
#
# 如果不会，那次瘦身就等于把细则删了。这个假设此前**一次都没验过** ——
# 本仓的规矩是「标了『没实测』之后就该去测」。
#
# 做法：两个脚手架项目，同一句话，headless 跑，从 stream-json 里看有没有
#       Skill(spec-github-bridge) 的 tool_use。
#
#   A 组 = 写了 15 行声明块        —— 靠块里那句触发指令
#   B 组 = 零足迹(--no-claude-md)  —— 靠 hook 注入的触发指令(0.7.5 起)
#
# **两组都必须加载。** 它们走的是两条不同的通路,但要的是同一个结果。
#
# ── 历史结果（别删，它是判据变过的理由）──
#   2026-08-27 首跑（0.7.4）：A 第 8 个工具调用加载；**B 全程没加载**，
#     转头按自己的想法设计表结构、问技术栈。当时判据写的是「A 加载 && B 不加载」，
#     结论读成「声明块起作用了」。
#   同日复跑（0.7.5，hook 给零足迹补了触发指令后）：**B 变成第 1 个工具调用就加载**，
#     随后拒绝编造验收标准、明确拒绝建 todo.md、提出开 feat/identity 模块分支。
#   → 判据据此改成「两组都必须加载」。首跑那份数据其实同时回答了两个问题，
#     而当时只问了一个 —— 见 CHANGELOG 0.7.5。
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
REPO="$(cd "$HERE/.." && pwd)"
PLUG="${REPO}/plugins/spec-guard"
# shellcheck source=evals/_preflight.sh
. "${HERE}/_preflight.sh"
PROMPT="帮我开始做 identity 模块的下一个任务"
WORK="${TMPDIR:-/tmp}/spec-guard-eval-$$"

grade() {  # $1=jsonl  $2=组名 ; 退出码 0=加载了 1=没加载 2=评测没跑起来
  if [ ! -s "$1" ]; then
    echo "  [$2] ❌ transcript 是空的 —— **评测没跑起来**（claude 未登录/参数错/网络？），"
    echo "  [$2]    这不是「skill 没被加载」的证据。"
    return 2
  fi
  python3 - "$1" "$2" <<'PY'
import sys, json
path, arm = sys.argv[1], sys.argv[2]
tools, skills = [], []
saw_assistant = False
for line in open(path, encoding='utf-8'):
    try: e = json.loads(line)
    except Exception: continue
    if not isinstance(e, dict) or e.get('type') != 'assistant': continue
    saw_assistant = True
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
if not saw_assistant:
    print(f"  [{arm}] ❌ transcript 里没有一条 assistant 事件 —— **评测没跑起来**，"
          f"这不是「skill 没被加载」的证据")
    sys.exit(2)
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

verdict() {  # $1=A 码 $2=B 码
  if [ "$1" -eq 2 ] || [ "$2" -eq 2 ]; then
    echo "  ⏭  评测没跑起来 —— **没有结论**，不要读成「通路失效」"
    return 2
  fi
  if [ "$1" -eq 0 ] && [ "$2" -eq 0 ]; then
    echo "  ✅ 两条通路都能让 skill 被加载"; return 0
  fi
  echo "  ⚠️  有通路失效了（两组都应加载）"; return 1
}

if [ "$MODE" = grade ]; then
  grade "$DIR/armA.jsonl" "A 声明块"; A=$?
  grade "$DIR/armB.jsonl" "B 零足迹"; B=$?
  verdict "$A" "$B"; exit $?
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

if [ "$MODE" = run ]; then
  preflight_installed_matches_repo "$REPO" || exit 1
fi

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
# B 组和 A 组一样要硬失败：B 靠 hook 注入那句触发指令，hook 一静默，
# 这一组测的就是空气 —— 跟 A 组同一个理由，此前这里只 warn 是不对称的。
if [ -z "$(CLAUDE_PROJECT_DIR="$WORK/armB" CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUG/hooks/phase-guard.sh" 2>/dev/null)" ]; then
  echo "  ❌ B 组上 hook 静默 —— 零足迹靠的就是 hook 注入的那句触发指令，评测无意义"
  echo "     （B 组有 .agent/state.json，0.7.0 起它本身就是激活信号，静默说明脚手架坏了）"
  exit 1
fi
echo "  ✅ B 组 hook 已激活（靠 .agent/state.json，即 --no-claude-md 零足迹模式）"

[ "$MODE" = scaffold ] && { echo "  --scaffold-only：到此为止，未调用模型"; exit 0; }

for arm in A B; do
  echo "  跑 $arm 组…"
  # 首跑时 A 组是在**第 8 个**工具调用才加载 skill，而上限当时正好是 8 ——
  # 差一步就会被截断、判成「没加载」的假阴性。抬到 12。
  run_headless "$WORK/arm$arm" "$WORK/arm$arm.jsonl" \
    -p "$PROMPT" --output-format stream-json --verbose --max-turns 12 \
    --allowedTools Read Glob Grep Skill || true
done

grade "$WORK/armA.jsonl" "A 声明块"; A=$?
grade "$WORK/armB.jsonl" "B 零足迹"; B=$?
verdict "$A" "$B"; exit $?
