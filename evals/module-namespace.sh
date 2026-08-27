#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# module-namespace —— 验插件的**头号卖点**
#
#   README 问题①：「四个模块递归跑下来，第二个模块的 /plan 会覆盖第一个的
#   tasks/plan.md」。插件的对策是 tasks/<module-id>/ 命名空间。
#
# 这条从立项起就写在 README 第一段，**从没被行为验证过**。
# 单测只验了 hook 的状态机（文件在不在），没验模型拿到约定后**真的会不会**
# 把产物放进命名空间。
#
# 为什么挑 local 模式：
#   - github 模式的两条通路已经验过（evals/skill-deferral.sh）
#   - local 模式**没有 skill 兜底**，13 行的块就是全部约定 —— 它不 work 就是真不 work
#   - local 是上游原生路径，新用户更可能从这儿进来
#
# 做法：两个脚手架（有块 / 无块），同一句「为 identity 拆任务」，
#       跑完看产物落在哪。这次判据是**文件系统**，不是 transcript ——
#       比读模型说了什么客观。
#
# ⚠️ 会真的调模型并允许它写文件（写在临时目录里）。不接进 validate.sh。
#
# 用法:
#   bash evals/module-namespace.sh
#   bash evals/module-namespace.sh --scaffold-only
# ─────────────────────────────────────────────────────────────
set -uo pipefail

MODE=run
[ "${1:-}" = "--scaffold-only" ] && MODE=scaffold

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUG="$(cd "$HERE/.." && pwd)/plugins/spec-guard"
PROMPT="为 identity 模块拆任务，产出计划和任务清单文件"
WORK="${TMPDIR:-/tmp}/spec-guard-ns-$$"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck source=evals/_preflight.sh
. "${HERE}/_preflight.sh"

mk() {  # $1=目录 $2=with|without
  rm -rf "$1"; mkdir -p "$1/spec"; ( cd "$1" && git init -q )
  printf '# CLAUDE.md\n\n身份服务。构建 `npm run build`，测试 `npm test`。\n' > "$1/CLAUDE.md"
  if [ "$2" = with ]; then
    {
      echo ""
      echo "<!-- BEGIN:agent-skills-convention -->"
      cat "$PLUG/templates/claude-block-local.md"
      echo "<!-- END:agent-skills-convention -->"
    } >> "$1/CLAUDE.md"
    mkdir -p "$1/.agent"
    echo '{"tracker":"none","modules":{"identity":{}},"activeModule":"identity"}' > "$1/.agent/state.json"
  fi
  printf '# 能力图\n\n| Module id | 职责 | Depends on |\n|---|---|---|\n| identity | 认证 | — |\n| billing | 计费 | identity |\n\n- [x] 已评审\n' > "$1/spec/CAPABILITY-MAP.md"
  printf '# identity\n\n验收：用户能注册、登录、登出。会话 30 天过期。\n' > "$1/spec/identity.md"
  ( cd "$1" && git add -A >/dev/null && git -c user.email=t@t -c user.name=t commit -qm init )
}

judge() {  # $1=目录 $2=组名 ; 0=落进命名空间 1=落错位置 2=什么都没产出
  local ns=0 flat=0
  [ -f "$1/tasks/identity/plan.md" ] && ns=$((ns+1))
  [ -f "$1/tasks/identity/todo.md" ] && ns=$((ns+1))
  [ -f "$1/tasks/plan.md" ] && flat=$((flat+1))
  [ -f "$1/tasks/todo.md" ] && flat=$((flat+1))
  echo "  [$2] tasks/ 下的产物：$(cd "$1" && find tasks -type f 2>/dev/null | sort | tr '\n' ' ' || echo '(无)')"
  echo "  [$2] 命名空间产物 ${ns}/2 · 根下单例产物 ${flat}"
  # 「一个产物都没有」和「产物落错位置」是两回事。前者多半是模型压根没跑
  # （或没写文件），把它读成「命名空间不成立」就是拿工具故障去指控产品 ——
  # 这个仓库对假警报的态度写在三条不可违反的性质里。
  if [ "${ns}" -eq 0 ] && [ "${flat}" -eq 0 ]; then
    echo "  [$2] ⏭  tasks/ 下什么都没有 —— 模型没产出任何任务文件，**这一组没有结论**"
    return 2
  fi
  [ "$ns" -ge 1 ] && [ "$flat" -eq 0 ]
}

if [ "$MODE" != scaffold ]; then
  preflight_installed_matches_repo "$REPO" || exit 1
fi

mkdir -p "$WORK"
mk "$WORK/withblk" with
mk "$WORK/noblk" without
echo "  脚手架: $WORK"
echo "  有块 CLAUDE.md $(wc -l < "$WORK/withblk/CLAUDE.md" | tr -d ' ') 行 · 无块 $(wc -l < "$WORK/noblk/CLAUDE.md" | tr -d ' ') 行"
if [ -z "$(CLAUDE_PROJECT_DIR="$WORK/withblk" CLAUDE_PLUGIN_ROOT="$PLUG" bash "$PLUG/hooks/phase-guard.sh" 2>/dev/null)" ]; then
  echo "  ❌ 有块那组 hook 静默 —— 脚手架没激活约定，评测无意义"; exit 1
fi
echo "  ✅ 有块那组 hook 已激活"

[ "$MODE" = scaffold ] && { echo "  --scaffold-only：到此为止，未调用模型"; exit 0; }

RUNFAIL=0
for d in withblk noblk; do
  echo "  跑 $d …"
  # 原先是 `>/dev/null 2>&1` —— claude 跑不起来时 tasks/ 空着，judge 于是
  # 打出「插件的头号卖点不成立」。**拿工具故障去指控产品**，正是本仓最忌的那类。
  run_headless "$WORK/$d" "$WORK/$d.out" \
    -p "$PROMPT" --max-turns 12 --allowedTools Read Glob Grep Skill Write Edit \
    || RUNFAIL=1
done
if [ "${RUNFAIL}" -ne 0 ]; then
  echo ""
  echo "  ⏭  评测没跑起来 —— **没有结论**，不要读成「卖点不成立」"
  exit 2
fi

echo ""
judge "$WORK/withblk" "有块"; W=$?
judge "$WORK/noblk"   "无块"; N=$?
echo ""
if [ "$W" -eq 2 ]; then
  echo "  ⏭  有块那组什么都没产出 —— **没有结论**，不要读成「卖点不成立」"
  exit 2
fi
if [ "$W" -eq 0 ]; then
  echo "  ✅ 有约定时产物落进 tasks/<module>/ 命名空间 —— 头号卖点成立"
  [ "$N" -ne 0 ] && echo "  ℹ  无约定时落在 tasks/ 根下（上游默认行为，正是要治的那个）"
  exit 0
fi
echo "  ❌ 有约定时产物**没有**落进命名空间 —— 插件的头号卖点不成立"
exit 1
