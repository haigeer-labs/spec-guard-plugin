# shellcheck shell=bash
# ─────────────────────────────────────────────────────────────
# evals 共用前置检查。被 source，不单独执行。
#
# 为什么需要它：两个评测都用 `claude -p` 在脚手架目录里跑，而那条命令加载的是
# **装着的那份插件**（user scope），不是这个仓库的工作副本。可脚手架的声明块
# 是从仓库的 templates/ 拷的，自检也是拿 CLAUDE_PLUGIN_ROOT 指着仓库跑的 ——
# 两者一旦不一致，「✅ hook 已激活」说的就是另一份代码，评测结论无从解释。
# 这正是 CHANGELOG 里记过的「新约定 + 旧检查器」中间态，只不过发生在评测里。
# ─────────────────────────────────────────────────────────────

# 装着的插件内容必须与仓库一致。不一致就别烧 token 了。
preflight_installed_matches_repo() {  # $1=仓库根
  local repo="$1" inst
  inst=$(python3 -c "
import json, os, sys
try:
    d = json.load(open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')))
    print(d['plugins']['spec-guard@spec-guard-marketplace'][0]['gitCommitSha'])
except Exception:
    pass" 2>/dev/null)
  if [ -z "${inst}" ]; then
    echo "  ❌ 读不到已安装的 spec-guard —— \`claude -p\` 里 hook 不会跑，评测无意义"
    echo "     先 /plugin install，或跑 claude plugin update"
    return 1
  fi
  if ! git -C "${repo}" merge-base --is-ancestor "${inst}" HEAD 2>/dev/null; then
    echo "  ❌ 装着的 ${inst:0:7} 不是当前 HEAD 的祖先 —— 版本关系不明，评测结论无从解释"
    return 1
  fi
  if ! git -C "${repo}" diff --quiet "${inst}" HEAD -- plugins/spec-guard 2>/dev/null; then
    echo "  ❌ 装着的插件内容与仓库不一致（装着 ${inst:0:7}）——"
    echo "     评测跑的是装着的那份，而脚手架和自检用的是仓库这份。先发版并 update："
    echo "       claude plugin marketplace update spec-guard-marketplace"
    echo "       claude plugin update spec-guard@spec-guard-marketplace   # 之后要重启"
    return 1
  fi
  echo "  ✅ 装着的插件内容与仓库一致（${inst:0:7}）"
  return 0
}

# 跑一次 headless claude，并把「没跑起来」和「跑了但结果不对」分开。
# 前者是工具故障，绝不能算成产品缺陷 —— 那是本仓最看重的那类误报。
run_headless() {  # $1=工作目录 $2=stdout 落盘路径 ; 其余=claude 参数
  local dir="$1" out="$2"; shift 2
  ( cd "${dir}" && claude "$@" ) > "${out}" 2> "${out}.err"
  local rc=$?
  if [ "${rc}" -ne 0 ]; then
    echo "  ❌ claude 退出码 ${rc} —— **评测没跑起来**，这不是产品的结论"
    sed -n '1,5p' "${out}.err" | sed 's/^/     /'
    return 2
  fi
  if [ ! -s "${out}" ]; then
    echo "  ❌ claude 退 0 但没有任何输出 —— **评测没跑起来**，这不是产品的结论"
    return 2
  fi
  return 0
}
