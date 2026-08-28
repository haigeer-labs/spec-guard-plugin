#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 装 pre-push 钩子。
#
# 为什么需要：本仓的 GitHub Actions **从 v0.1.0 至今跑过 0 次**
# （账户级 Actions 被禁，`gh api .../actions/runs` → total_count: 0）。
# 也就是说 114 条 hook 断言、22 条校验器断言、shellcheck 全部依赖
# **一个人记得在自己机器上敲那三条命令**。这个钩子是止血带，不是解药 ——
# 真正的解法是把 Actions 恢复。
#
# 钩子只跑不花钱的那几层；变异测试和会调模型的 evals 不在里面。
# 急着推可以 `git push --no-verify` 绕过，但那就回到了「靠自觉」。
#
# 用法: bash scripts/install-git-hooks.sh [--uninstall]
# ─────────────────────────────────────────────────────────────
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$(git -C "${ROOT}" rev-parse --git-path hooks 2>/dev/null)"
case "${DIR}" in /*) ;; *) DIR="${ROOT}/${DIR}" ;; esac
HOOK="${DIR}/pre-push"

if [ "${1:-}" = "--uninstall" ]; then
  [ -f "${HOOK}" ] && rm -f "${HOOK}" && echo "✅ 已移除 ${HOOK}" || echo "⏭  没装过"
  exit 0
fi

if [ -f "${HOOK}" ] && ! grep -q "spec-guard-pre-push" "${HOOK}" 2>/dev/null; then
  echo "❌ ${HOOK} 已存在且不是本脚本装的 —— 不覆盖别人的钩子，请人工合并"
  exit 1
fi

mkdir -p "${DIR}"
cat > "${HOOK}" <<'PRE'
#!/usr/bin/env bash
# spec-guard-pre-push —— 由 scripts/install-git-hooks.sh 生成
# 绕过: git push --no-verify
set -uo pipefail
R="$(git rev-parse --show-toplevel)"
echo "── pre-push: 跑不花钱的那几层 ──"
F=0
# 每样只跑**一遍**，输出留在变量里。跑两遍（一遍取输出一遍取退出码）
# 会把 50 秒变成 100 秒，而 pre-push 慢到让人条件反射加 --no-verify
# 就等于没装。
chk() {  # $1=说明 其余=命令
  local name="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '  ✅ %s —— %s\n' "$name" "$(printf '%s' "$out" | tail -1 | sed 's/^ *//')"
  else
    printf '  ❌ %s\n' "$name"
    # 只捞真正的失败行：断言说明里带「失败」二字的正例会被宽 grep 捞进来
    printf '%s\n' "$out" | grep -E "^ *❌|[1-9][0-9]* 失败" | head -8 | sed 's/^/     /'
    F=1
  fi
}
# 显式 /bin/bash：macOS 自带的 3.2 才是这个项目踩过坑的那个版本
chk "validate"          /bin/bash "$R/scripts/validate.sh"
chk "phase-guard"       /bin/bash "$R/plugins/spec-guard/hooks/test-phase-guard.sh"
chk "verify-artifacts"  /bin/bash "$R/plugins/spec-guard/hooks/test-verify-artifacts.sh"
if [ "$F" -ne 0 ]; then
  echo "❌ 有检查没过 —— push 中止。细节见上面，或单独跑那三条；"
  echo "   确实要推: git push --no-verify"
  exit 1
fi
echo "✅ 全绿，继续 push"
PRE
chmod +x "${HOOK}"
echo "✅ 已装 ${HOOK}"
echo "   它会跑 validate.sh + 两套 hook 断言（约 50 秒）。绕过: git push --no-verify"
