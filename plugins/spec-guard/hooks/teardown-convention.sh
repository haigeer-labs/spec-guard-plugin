#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# teardown-convention.sh —— 从当前项目移除 spec-guard 约定（确定性执行）
#
# 为什么要有这个脚本：teardown 是插件里**唯一的破坏性操作**（删用户
# CLAUDE.md 里的内容），此前却完全交给模型按 .md 里的步骤做，零测试。
# 而本仓的规矩是「写文件是幂等性和安全性要求高的操作，不能有非确定性」——
# setup 早就是脚本了，teardown 一直不是。
#
# 更要命的是它此前**移除不干净**：0.7.0 起 `.agent/state.json` 也是激活信号，
# 而 teardown 明确不删它 —— 于是删完声明块，项目不是「约定被移除」，
# 是**变成了零足迹模式**；0.7.5 之后 hook 还会每轮注入「先加载 skill」，
# 比移除前更黏。命令文里那句「无输出即为成功」也就成了假的。
#
# 用法:
#   bash teardown-convention.sh [--dry-run] [--keep-state]
#
#   --keep-state  保留 .agent/state.json 原名。**hook 会继续激活**（零足迹模式），
#                 只在你确实想切到那个模式时才用。
#
# 默认行为：把 state.json 改名为 state.json.disabled —— 既让 hook 真的停，
# 又不丢 issue 编号映射（删了就找不回来）。
# ─────────────────────────────────────────────────────────────
set -uo pipefail

DRY=false; KEEP=false; HOST=claude; SEEN=""; HOST_SET=false
for a in "$@"; do
  case " $SEEN " in *" $a "*) echo "重复参数: $a" >&2; exit 2 ;; esac
  SEEN="$SEEN $a"
  case "$a" in
    --dry-run)    DRY=true ;;
    --keep-state) KEEP=true ;;
    --host=claude) [ "$HOST_SET" = false ] || { echo "host 只能指定一次" >&2; exit 2; }; HOST=claude; HOST_SET=true ;;
    --host=codex)  [ "$HOST_SET" = false ] || { echo "host 只能指定一次" >&2; exit 2; }; HOST=codex; HOST_SET=true ;;
    --host=*)      echo "host 必须是 claude 或 codex"; exit 2 ;;
    *)             echo "未知参数: $a" >&2; exit 2 ;;
  esac
done

# ── 作用目录：项目根，不是当前 shell 的 cwd ────────────────
#   会话里的工作目录是会被 `cd` 改掉的。从子目录跑的话，本脚本会去删
#   **子目录**里那份并不存在的声明块，然后报「什么都没做」退 2 ——
#   而根上的约定原封不动还在。移除操作报成功却没移除，比报错更坏。
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${ROOT}" 2>/dev/null || { echo "❌ 进不去项目根: ${ROOT}"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCK_TOOL="$HERE/managed-block.py"
[ -f "$BLOCK_TOOL" ] || { echo "❌ 缺少声明块安全工具: $BLOCK_TOOL" >&2; exit 1; }

case "$HOST" in
  claude)
    INSTRUCTIONS=CLAUDE.md
    MARK_B="<!-- BEGIN:agent-skills-convention -->"
    MARK_E="<!-- END:agent-skills-convention -->"
    OTHER_HOST=Codex
    OTHER_INSTRUCTIONS=AGENTS.md
    OTHER_MARK_B="<!-- BEGIN:spec-guard-codex-convention -->"
    ;;
  codex)
    INSTRUCTIONS=AGENTS.md
    MARK_B="<!-- BEGIN:spec-guard-codex-convention -->"
    MARK_E="<!-- END:spec-guard-codex-convention -->"
    OTHER_HOST=Claude
    OTHER_INSTRUCTIONS=CLAUDE.md
    OTHER_MARK_B="<!-- BEGIN:agent-skills-convention -->"
    ;;
esac
STATE=".agent/state.json"

# 任何无效的目标声明块都要在 state 处理前拒绝，避免“块没拆掉、state 却被停用”的半完成状态。
HAS_TARGET_MARKER=false
if [ -f "$INSTRUCTIONS" ]; then
  if grep -Fq "$MARK_B" "$INSTRUCTIONS" 2>/dev/null; then
    HAS_TARGET_MARKER=true
  elif grep -Fq "$MARK_E" "$INSTRUCTIONS" 2>/dev/null; then
    HAS_TARGET_MARKER=true
  fi
fi
if [ "$HAS_TARGET_MARKER" = true ]; then
  python3 "$BLOCK_TOOL" validate "$INSTRUCTIONS" "$MARK_B" "$MARK_E" >/dev/null || exit 1
fi

act()  { [ "$DRY" = true ] && printf '  [dry-run] %s\n' "$1" || printf '  ✅ %s\n' "$1"; }
skip() { printf '  ⏭  %s\n' "$1"; }
note() { printf '  ℹ  %s\n' "$1"; }

echo "═══ 移除 spec-guard 约定 ═══"
echo "  作用目录: ${ROOT}"

DID=0
OTHER_ACTIVE=false
if [ -f "$OTHER_INSTRUCTIONS" ] && grep -q "$OTHER_MARK_B" "$OTHER_INSTRUCTIONS" 2>/dev/null; then
  OTHER_ACTIVE=true
fi

# ── 1. 指令文件的声明块 ──
if [ -f "$INSTRUCTIONS" ] && grep -Fq "${MARK_B}" "$INSTRUCTIONS" 2>/dev/null; then
  if [ "$DRY" = true ]; then
    N=$(python3 "$BLOCK_TOOL" validate "$INSTRUCTIONS" "$MARK_B" "$MARK_E") || exit 1
  else
    N=$(python3 "$BLOCK_TOOL" remove "$INSTRUCTIONS" "$MARK_B" "$MARK_E") || exit 1
  fi
  act "${INSTRUCTIONS} 声明块已移除（${N} 行，标记外一个字节不动）"
  DID=1
else
  skip "${INSTRUCTIONS} 里没有声明块"
fi

# ── 2. 激活信号：state.json ──
#   这一步是 teardown 真正「移除」的关键。删掉声明块但留着 state.json，
#   hook 照常激活，只是切到零足迹模式 —— 那不是移除。
if [ -f "${STATE}" ]; then
  if [ "${KEEP}" = true ]; then
    note "保留 ${STATE}（--keep-state）—— **hook 仍会激活**，项目变成零足迹模式"
  elif [ "$OTHER_ACTIVE" = true ]; then
    note "保留 ${STATE}—— ${OTHER_HOST} 声明块仍在，host 继续激活"
  else
    [ "${DRY}" = false ] && mv "${STATE}" "${STATE}.disabled"
    act "${STATE} → ${STATE}.disabled（hook 就此停用，issue 编号映射保留）"
    DID=1
  fi
else
  skip "没有 ${STATE}"
fi

echo ""
if [ "${DID}" -eq 0 ]; then
  echo "本项目没有启用 spec-guard 约定，什么都没做。"
  exit 2
fi

# ── 3. 验证：hook 真的停了吗 ──
#   命令文里原来写「无输出即为成功」,但那句话在 0.7.0 之后就不成立了。
#   这里实际跑一遍,而不是让人相信一句话。
if [ "${DRY}" = false ] && [ "$OTHER_ACTIVE" = false ]; then
  # 兜底到脚本自己旁边的那份 —— setup-convention.sh 一直是这么做的，
  # 这里没跟上：CLAUDE_PLUGIN_ROOT 没设时自检整段被跳过，而
  # 「实际跑一遍而不是让人相信一句话」正是 0.7.9 把 teardown 改成脚本的唯一理由。
  HK="${CLAUDE_PLUGIN_ROOT:-}/hooks/phase-guard.sh"
  [ -f "${HK}" ] || HK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/phase-guard.sh"
  if [ -f "${HK}" ]; then
    if [ -z "$(CLAUDE_PROJECT_DIR="$(pwd)" bash "${HK}" 2>/dev/null)" ]; then
      echo "  ✅ 已验证：hook 不再注入任何内容"
    else
      echo "  ⚠️  hook 仍在注入 —— 检查是否还有别的激活信号"
    fi
  else
    note "找不到 phase-guard.sh，跳过验证（CLAUDE_PLUGIN_ROOT 未设置？）"
  fi
elif [ "${DRY}" = false ]; then
  note "${OTHER_HOST} 声明块仍在，hook 继续激活"
fi

cat <<'EOF'

以下内容**保留**，确认不需要后自行删除：
  spec/                     你的能力图和模块规格
  tasks/                    你的计划文档
  .agent/state.json.disabled  模块 ↔ issue 编号映射（改回原名即可恢复约定）

GitHub 上已创建的 issue 不受影响。
插件本身仍然装着。要完全卸载：/plugin uninstall spec-guard
EOF
