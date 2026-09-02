#!/usr/bin/env bash
# 仓库完整性校验。CI 和本地共用。
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
F=0
say(){ printf "  %s %s\n" "$1" "$2"; }

echo "═══ 结构 ═══"
for p in .claude-plugin/marketplace.json \
         plugins/spec-guard/.claude-plugin/plugin.json \
         plugins/spec-guard/hooks/hooks.json \
         plugins/spec-guard/hooks/phase-guard.sh; do
  [ -f "$p" ] && say "✅" "$p" || { say "❌" "$p 缺失"; F=1; }
done

echo ""
echo "═══ JSON 语法 ═══"
while IFS= read -r j; do
  python3 -m json.tool "$j" >/dev/null 2>&1 && say "✅" "$j" || { say "❌" "$j 解析失败"; F=1; }
done < <(find . -name "*.json" -not -path "./.git/*")

echo ""
echo "═══ marketplace ↔ Claude / Codex plugin 一致性 ═══"
python3 scripts/check-manifests.py || F=1

echo ""
echo "═══ Shell 语法 ═══"
while IFS= read -r s; do
  bash -n "$s" 2>/dev/null && say "✅" "$s" || { say "❌" "$s 语法错误"; F=1; }
done < <(find . -name "*.sh" -not -path "./.git/*")

echo ""
echo "═══ 可执行位 ═══"
while IFS= read -r s; do
  [ -x "$s" ] && say "✅" "$s" || { say "⚠️ " "$s 缺执行位（git update-index --chmod=+x ${s}）"; }
done < <(find . -name "*.sh" -not -path "./.git/*")

echo ""
echo "═══ bash 3.2 兼容（macOS 自带 bash）═══"
# shellcheck disable=SC2046
python3 scripts/check-bash32.py $(find . -name "*.sh" -not -path "./.git/*") || F=1

echo ""
echo "═══ gh --json 字段是否真实存在 ═══"
# shellcheck disable=SC2046
python3 scripts/check-gh-json-fields.py \
  $(find plugins scripts -type f \( -name "*.md" -o -name "*.sh" \)) || F=1

echo ""
echo "═══ 管道 + grep -q（SIGPIPE 陷阱）═══"
# shellcheck disable=SC2046
python3 scripts/check-grep-pipe.py $(find . -name "*.sh" -not -path "./.git/*") || F=1

echo ""
echo "═══ 用户可见输出里的命令名 ═══"
python3 scripts/check-command-names.py || F=1

echo ""
echo "═══ 校验器自身的回归 ═══"
bash scripts/test-checkers.sh || F=1
echo ""

# 指纹算法是两个 hook 和 /sync-map 共用的那一份 —— 它自己算错，
# 表现就是一条关不掉的假警报。免费，所以进这一层。
echo "═══ 指纹算法自检 ═══"
python3 plugins/spec-guard/hooks/spec-digest.py --selftest || F=1
echo ""

echo "═══ Capability history ledger regression ═══"
/bin/bash plugins/spec-guard/hooks/test-capability-history.sh || F=1
echo ""

echo "═══ Initiative lifecycle regression ═══"
/bin/bash plugins/spec-guard/hooks/test-initiative-lifecycle.sh || F=1
echo ""

echo "═══ History verification regression ═══"
/bin/bash plugins/spec-guard/hooks/test-history-verification.sh || F=1
echo ""

echo "═══ Codex 适配器回归 ═══"
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh || F=1
echo ""

echo "═══ Codex 真实宿主 smoke 判决器自检（不调用 Codex）═══"
/bin/bash evals/codex-plugin-smoke.sh --selftest || F=1
echo ""

# 评测的判决器也归这一层：真跑要花 token，但「判决器会不会永远打绿灯」
# 不用花钱就能验 —— 喂已知坏输入必须非零退出。
echo "═══ 评测判决器自身的回归（不调模型）═══"
bash evals/next-redo.sh --selftest || F=1
bash evals/sync-map.sh  --selftest || F=1
echo ""

echo "═══ README 内嵌声明块 ↔ templates ═══"
python3 scripts/check-readme-sync.py || F=1
echo ""

echo "═══ 命令 frontmatter ═══"
while IFS= read -r c; do
  grep -q -- "---" <<<"$(head -1 "$c")" && say "✅" "$c" || { say "❌" "$c 缺 frontmatter"; F=1; }
done < <(find plugins/*/commands -name "*.md" 2>/dev/null)

echo ""
[ "$F" -eq 0 ] && echo "校验通过 ✅" || echo "校验失败 ❌"
exit $F
