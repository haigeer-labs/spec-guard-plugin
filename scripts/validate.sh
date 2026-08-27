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
echo "═══ marketplace ↔ plugin 一致性 ═══"
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
echo "═══ 用户可见输出里的命令名 ═══"
python3 scripts/check-command-names.py || F=1

echo ""
echo "═══ 命令 frontmatter ═══"
while IFS= read -r c; do
  grep -q -- "---" <<<"$(head -1 "$c")" && say "✅" "$c" || { say "❌" "$c 缺 frontmatter"; F=1; }
done < <(find plugins/*/commands -name "*.md" 2>/dev/null)

echo ""
[ "$F" -eq 0 ] && echo "校验通过 ✅" || echo "校验失败 ❌"
exit $F
