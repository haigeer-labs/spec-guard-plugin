#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# scripts/check-*.py 的回归测试。
#
# 为什么需要它：本仓一轮之内出过**四次**「新加的防线自己有毛病」——
#   1. check-command-names 漏了双引号前缀，抓不到 NEXT="/plan …"，
#      也就抓不到它本该抓的那个 bug
#   2. check-readme-sync 第一版没跑过反向用例
#   3. 发版流程的 sha 核对拿 HEAD 比，文档提交就误报
#   4. evals 的判分把 skill 名写死成裸名，把一次成功判成失败
#
# 四次同一个形状：**判据写完没有当场用真实数据跑一遍。**
# 「防线本身也要被测试」这条一直写在 CLAUDE.md 里，但它是句口号，
# 不是套件 —— 所以每次都靠人自觉，而四次里零次做到。
#
# 每个校验器两个用例：喂已知坏输入必须**非零退出**，喂好输入必须**零退出**。
# 反向用例是重点：一个永远返回 0 的校验器和没有校验器没区别。
# ─────────────────────────────────────────────────────────────
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

want() {  # $1=期望(fail|pass) $2=用例名 $3...=命令
  local exp="$1" name="$2"; shift 2
  "$@" >/dev/null 2>&1; local rc=$?
  if { [ "$exp" = fail ] && [ "$rc" -ne 0 ]; } || { [ "$exp" = pass ] && [ "$rc" -eq 0 ]; }; then
    printf '  ✅ %s\n' "$name"; PASS=$((PASS+1))
  else
    printf '  ❌ %s（期望 %s，实际退出码 %s）\n' "$name" "$exp" "$rc"; FAIL=$((FAIL+1))
  fi
}

echo "═══ check-*.py 回归 ═══"

# ── check-bash32.py ──
# 踩过的真 bug：$VAR 紧跟全角字符时，bash 3.2 把首字节吃进变量名
# 坏样本在**运行时拼装**，不让这个模式出现在本文件源码里 ——
# 否则 validate.sh 里的 check-bash32 会抓自己的测试脚本。
# 用豁免（跳过 test-*.sh）也能过，但那会削掉真实覆盖：测试脚本本身
# 也得能在 bash 3.2 上跑。
D='$'
printf 'X=1\necho "（#%sISSUE）"\n'    "$D" > "$TMP/bad32.sh"
printf 'X=1\necho "（#%s{ISSUE}）"\n' "$D" > "$TMP/good32.sh"
want fail "bash32: \$VAR 紧跟全角括号 → 报错" python3 "$ROOT/scripts/check-bash32.py" "$TMP/bad32.sh"
want pass "bash32: \${VAR} 写法 → 放行"       python3 "$ROOT/scripts/check-bash32.py" "$TMP/good32.sh"

# ── check-grep-pipe.py ──
# 踩过的真 bug（三次）：`cmd | grep -q` 里 grep 命中即关管道，上游吃 SIGPIPE(141)，
# pipefail 传出 → 判断永远为假。坏样本同样**运行时拼装**，理由和上面那条一样：
# 写成字面量的话 validate.sh 里的 check-grep-pipe 会抓自己的测试脚本。
Q='q'
printf 'f(){ head -1 x | grep -%s pat; }\n' "$Q" > "$TMP/badgp.sh"
printf 'f(){ grep -%s pat <<<"$(head -1 x)"; }\n' "$Q" > "$TMP/goodgp.sh"
printf '# 注释里写 cmd | grep -%s 是允许的\necho ok\n' "$Q" > "$TMP/cmtgp.sh"
want fail "grep-pipe: 管道 + grep -q → 报错"   python3 "$ROOT/scripts/check-grep-pipe.py" "$TMP/badgp.sh"
want pass "grep-pipe: herestring 写法 → 放行"  python3 "$ROOT/scripts/check-grep-pipe.py" "$TMP/goodgp.sh"
want pass "grep-pipe: 注释里提到不算 → 放行"   python3 "$ROOT/scripts/check-grep-pipe.py" "$TMP/cmtgp.sh"

# ── check-manifests.py ──
mkm() {  # $1=目录 $2=plugin.json 里的 name
  rm -rf "$1"; mkdir -p "$1/.claude-plugin" "$1/plugins/demo/.claude-plugin"
  printf '{"name":"m","owner":{"name":"t"},"plugins":[{"name":"demo","source":"./plugins/demo"}]}\n' \
    > "$1/.claude-plugin/marketplace.json"
  printf '{"name":"%s","version":"1.0.0","description":"d"}\n' "$2" > "$1/plugins/demo/.claude-plugin/plugin.json"
}
mkm "$TMP/mfbad" wrong-name
mkm "$TMP/mfgood" demo
want fail "manifests: marketplace 与 plugin.json 名称不一致 → 报错" \
  bash -c "cd '$TMP/mfbad' && python3 '$ROOT/scripts/check-manifests.py'"
want pass "manifests: 名称一致 → 放行" \
  bash -c "cd '$TMP/mfgood' && python3 '$ROOT/scripts/check-manifests.py'"

# ── check-command-names.py ──
mkc() {  # $1=目录 $2=模板里引用的命令名
  rm -rf "$1"; mkdir -p "$1/plugins/demo/commands" "$1/plugins/demo/templates" "$1/plugins/demo/skills"
  printf -- '---\ndescription: d\n---\n内容\n' > "$1/plugins/demo/commands/real.md"
  printf '跑一下 `/%s` 就好。\n' "$2" > "$1/plugins/demo/templates/t.md"
}
mkc "$TMP/cnbad" totally-made-up
mkc "$TMP/cngood" real
want fail "command-names: 模板引用不存在的命令 → 报错" \
  bash -c "cd '$TMP/cnbad' && python3 '$ROOT/scripts/check-command-names.py'"
want pass "command-names: 引用本插件真实命令 → 放行" \
  bash -c "cd '$TMP/cngood' && python3 '$ROOT/scripts/check-command-names.py'"

# 它自己声明「不查 hooks/test-*.sh」—— 这条豁免也要有用例，
# 否则下次有人收紧范围时会静默把它去掉（这正是 0.7.3 修过的那次）
mkc "$TMP/cnskip" real
mkdir -p "$TMP/cnskip/plugins/demo/hooks"
printf 'CLAUDE_PLUGIN_ROOT=/x/spec-guard/9.9.9 bash h.sh\n' > "$TMP/cnskip/plugins/demo/hooks/test-fake.sh"
want pass "command-names: hooks/test-*.sh 里的假路径被豁免" \
  bash -c "cd '$TMP/cnskip' && python3 '$ROOT/scripts/check-command-names.py'"
printf 'NEXT="/totally-made-up"\n' > "$TMP/cnskip/plugins/demo/hooks/real.sh"
want fail "command-names: 非 test- 的 hook 仍然要查" \
  bash -c "cd '$TMP/cnskip' && python3 '$ROOT/scripts/check-command-names.py'"

# ── check-readme-sync.py ──
mkr() {  # $1=目录 $2=README 内嵌块要不要跟模板一致(same|drift)
  rm -rf "$1"; mkdir -p "$1/plugins/spec-guard/templates"
  printf '## 约定\n\n- 一行事实\n' > "$1/plugins/spec-guard/templates/claude-block-github.md"
  printf '## 约定\n\n- 本地模式\n' > "$1/plugins/spec-guard/templates/claude-block-local.md"
  {
    echo "# README"; echo
    echo "<!-- SYNC:claude-block-github BEGIN -->"
    echo '````markdown'
    echo "<!-- BEGIN:agent-skills-convention -->"
    printf '## 约定\n\n- 一行事实\n'
    [ "$2" = drift ] && echo "- 多出来的一行（模板里没有）"
    echo "<!-- END:agent-skills-convention -->"
    echo '````'
    echo "<!-- SYNC:claude-block-github END -->"
    echo
    echo "<!-- SYNC:claude-block-local BEGIN -->"
    echo '````markdown'
    echo "<!-- BEGIN:agent-skills-convention -->"
    printf '## 约定\n\n- 本地模式\n'
    echo "<!-- END:agent-skills-convention -->"
    echo '````'
    echo "<!-- SYNC:claude-block-local END -->"
  } > "$1/README.md"
}
mkr "$TMP/rsbad" drift
mkr "$TMP/rsgood" same
want fail "readme-sync: README 与模板分叉 → 报错" python3 "$ROOT/scripts/check-readme-sync.py" "$TMP/rsbad"
want pass "readme-sync: 逐字节一致 → 放行"       python3 "$ROOT/scripts/check-readme-sync.py" "$TMP/rsgood"
rm -rf "$TMP/rsmissing"; mkdir -p "$TMP/rsmissing/plugins/spec-guard/templates"
printf 'x\n' > "$TMP/rsmissing/plugins/spec-guard/templates/claude-block-github.md"
printf 'y\n' > "$TMP/rsmissing/plugins/spec-guard/templates/claude-block-local.md"
printf '# README\n没有 SYNC 标记\n' > "$TMP/rsmissing/README.md"
want fail "readme-sync: README 里缺 SYNC 标记 → 报错" python3 "$ROOT/scripts/check-readme-sync.py" "$TMP/rsmissing"

echo ""
echo "  总计 $PASS 通过 / $FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
