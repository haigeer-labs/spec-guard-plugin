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

# ── check-gh-json-fields.py ──
# 踩过的真 bug（两次同一形状）：`gh issue list --parent`，以及 SKILL.md 里
# 一个并不存在的 issue view JSON 字段 —— 都是**每次跑都硬失败**的命令，
# 都在文档里躺了很久。这个校验器的判据不是冻结清单，是问 gh 本人。
# （这里刻意不写出那个字段名：校验器不跳过注释，写了会抓到本文件自己。）
# 坏样本**运行时拼装**，不让那个字段名以完整形态出现在本文件源码里 ——
# 否则 validate.sh 里的 check-gh-json-fields 会抓自己的测试脚本（同 bash32 那条）。
BADF='depend''encies'
printf 'gh issue view 5 --json title,%s\n' "$BADF" > "$TMP/badjson.md"
printf 'gh issue view 5 --json title,blockedBy\n'   > "$TMP/goodjson.md"
# 这里不能依赖 runner 预装 gh 的网络/认证状态。某些 CI 环境有 gh，但拿不到
# 字段表，校验器按设计会降级跳过，反向用例便会误判为通过。用最小 fake 固定
# `Available fields:` 输出，专门验证校验器的字段判定本身。
mkdir -p "$TMP/ghjson-bin"
printf '%s\n' '#!/bin/sh' \
  'printf "%s\\n" "Available fields:" "title" "blockedBy" >&2' \
  'exit 1' > "$TMP/ghjson-bin/gh"
chmod +x "$TMP/ghjson-bin/gh"
GHJSON_PATH="$TMP/ghjson-bin:$PATH"
want fail "gh-json: 不存在的字段 → 报错" \
  env PATH="$GHJSON_PATH" python3 "$ROOT/scripts/check-gh-json-fields.py" "$TMP/badjson.md"
want pass "gh-json: 真实字段 → 放行" \
  env PATH="$GHJSON_PATH" python3 "$ROOT/scripts/check-gh-json-fields.py" "$TMP/goodjson.md"
# gh 不可用时必须干净跳过退 0，不能假阻塞。
# PATH 清空后 python3 也找不着了，所以用绝对路径调它 —— 这里要屏蔽的只有 gh。
mkdir -p "$TMP/nogh"
PY3="$(command -v python3)"
want pass "gh-json: gh 不可用时干净跳过" \
  env PATH="$TMP/nogh" "$PY3" "$ROOT/scripts/check-gh-json-fields.py" "$TMP/badjson.md"

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

# Codex 清单在过渡期仍是可选的；一旦存在，就必须是 Claude 清单的镜像。
mkspecguard() {
  rm -rf "$1"; mkdir -p "$1/.claude-plugin" "$1/plugins/spec-guard/.claude-plugin"
  printf '{"name":"m","owner":{"name":"t"},"plugins":[{"name":"spec-guard","source":"./plugins/spec-guard"}]}\n' \
    > "$1/.claude-plugin/marketplace.json"
  printf '{"name":"spec-guard","version":"1.0.0","description":"d"}\n' \
    > "$1/plugins/spec-guard/.claude-plugin/plugin.json"
}
mkcodex() {  # $1=目录 $2=name $3=version $4=skills $5=hooks
  mkdir -p "$1/plugins/spec-guard/.codex-plugin"
  printf '{"name":"%s","version":"%s","skills":"%s","hooks":"%s"}\n' "$2" "$3" "$4" "$5" \
    > "$1/plugins/spec-guard/.codex-plugin/plugin.json"
}
mkspecguard "$TMP/codex-name-bad"
mkcodex "$TMP/codex-name-bad" wrong-name 1.0.0 ./skills/ ./hooks/hooks.json
want fail "codex manifest: 名称漂移 → 报错" \
  bash -c "cd '$TMP/codex-name-bad' && python3 '$ROOT/scripts/check-manifests.py'"
mkspecguard "$TMP/codex-version-bad"
mkcodex "$TMP/codex-version-bad" spec-guard 0.0.0 ./skills/ ./hooks/hooks.json
want fail "codex manifest: 版本漂移 → 报错" \
  bash -c "cd '$TMP/codex-version-bad' && python3 '$ROOT/scripts/check-manifests.py'"
mkspecguard "$TMP/codex-skills-bad"
mkcodex "$TMP/codex-skills-bad" spec-guard 1.0.0 skills/ ./hooks/hooks.json
want fail "codex manifest: skills 路径漂移 → 报错" \
  bash -c "cd '$TMP/codex-skills-bad' && python3 '$ROOT/scripts/check-manifests.py'"
mkspecguard "$TMP/codex-hooks-bad"
mkcodex "$TMP/codex-hooks-bad" spec-guard 1.0.0 ./skills/ hooks/hooks.json
want fail "codex manifest: hooks 路径漂移 → 报错" \
  bash -c "cd '$TMP/codex-hooks-bad' && python3 '$ROOT/scripts/check-manifests.py'"
mkspecguard "$TMP/codex-good"
mkcodex "$TMP/codex-good" spec-guard 1.0.0 ./skills/ ./hooks/hooks.json
want pass "codex manifest: 名称和版本一致 → 放行" \
  bash -c "cd '$TMP/codex-good' && python3 '$ROOT/scripts/check-manifests.py'"

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
printf '跑一下 `/demo:real` 就好。\n' >> "$TMP/cngood/plugins/demo/templates/t.md"
want pass "command-names: Claude 插件命名空间命令 → 放行" \
  bash -c "cd '$TMP/cngood' && python3 '$ROOT/scripts/check-command-names.py'"
printf '跑一下 `/demo:not-real` 就好。\n' >> "$TMP/cngood/plugins/demo/templates/t.md"
want fail "command-names: 命名空间里的不存在命令 → 报错" \
  bash -c "cd '$TMP/cngood' && python3 '$ROOT/scripts/check-command-names.py'"

# tracker 路由命令不能只是描述「调用 bridge」：真实 Claude 会把这种短句当成
# 背景信息而静默结束。必须点明加载 skill、执行哪项操作、以及写入前的确认边界。
if grep -q 'GitLab 使用确定性脚本' "$ROOT/plugins/spec-guard/commands/sync-map.md" \
   && grep -q '不要只复述路由规则或静默结束' "$ROOT/plugins/spec-guard/commands/sync-map.md" \
   && grep -q '完整执行其「操作三：next」' "$ROOT/plugins/spec-guard/commands/next.md" \
   && grep -q '完整执行其「操作四：deliver」' "$ROOT/plugins/spec-guard/commands/deliver.md" \
   && grep -q 'allowed-tools: Bash, Read, Write' "$ROOT/plugins/spec-guard/commands/sync-map.md"; then
  printf '  ✅ tracker 路由命令强制加载 bridge 并禁止静默结束\n'; PASS=$((PASS+1))
else
  printf '  ❌ tracker 路由命令缺少执行协议或所需工具权限\n'; FAIL=$((FAIL+1))
fi

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

# 上游清单不再是冻结快照，而是问本机装着的上游本人。
# 危险方向是**上游删名/改名**：快照里还有、上游已经没有 —— 检查器照样放行，
# 而文档里那条命令已经会报 Unknown。0.4.1 的 /planning 就是这么来的。
UPS=$(SPEC_GUARD_UPSTREAM_REGISTRY="" python3 -c "
import json,pathlib,sys
try:
    d=json.loads((pathlib.Path.home()/'.claude/plugins/installed_plugins.json').read_text())
    print(next(v[0]['installPath'] for k,v in d['plugins'].items() if 'agent-skills' in k and v))
except Exception: pass" 2>/dev/null)
if [ -n "${UPS}" ] && [ -d "${UPS}/.claude/commands" ]; then
  mkfake() {  # $1=目标目录 $2=要删掉的命令名（空=全留）
    rm -rf "$1"; mkdir -p "$1/.claude/commands" "$1/skills"
    for f in "${UPS}"/.claude/commands/*.md; do
      b=$(basename "$f"); [ "$b" = "$2.md" ] || : > "$1/.claude/commands/$b"
    done
    for d in "${UPS}"/skills/*/; do mkdir -p "$1/skills/$(basename "$d")"; done
    printf '{"plugins":{"agent-skills@x":[{"installPath":"%s"}]}}\n' "$1" > "$1.json"
  }
  mkfake "$TMP/upfull" ""
  mkfake "$TMP/upgone" plan
  want pass "command-names: 对照上游本人 → 放行" \
    bash -c "cd '$ROOT' && SPEC_GUARD_UPSTREAM_REGISTRY='$TMP/upfull.json' python3 '$ROOT/scripts/check-command-names.py'"
  want fail "command-names: 上游删了 /plan → 报快照过期" \
    bash -c "cd '$ROOT' && SPEC_GUARD_UPSTREAM_REGISTRY='$TMP/upgone.json' python3 '$ROOT/scripts/check-command-names.py'"
else
  printf '  ⏭  本机没装上游 agent-skills，跳过「对照上游本人」的一正一反（不代表通过）\n'
fi

# ── 零文件不算通过 ────────────────────────────────────────
# 「0 处违规」和「0 个文件」在退出码上长得一样（lenses A5）。
# validate.sh 里这三个都靠 $(find …) 喂文件，find 表达式一旦失配就会全绿。
for c in check-bash32 check-grep-pipe check-gh-json-fields; do
  want fail "$c: 零个文件 → 不算通过" python3 "$ROOT/scripts/$c.py"
done

# ── check-readme-sync.py ──
mkr() {  # $1=目录 $2=README 内嵌块要不要跟模板一致(same|drift)
  rm -rf "$1"; mkdir -p "$1/plugins/spec-guard/templates"
  printf '## 约定\n\n- 一行事实\n' > "$1/plugins/spec-guard/templates/claude-block-github.md"
  printf '## 约定\n\n- GitLab 模式\n' > "$1/plugins/spec-guard/templates/claude-block-gitlab.md"
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
    echo "<!-- SYNC:claude-block-gitlab BEGIN -->"
    echo '````markdown'
    echo "<!-- BEGIN:agent-skills-convention -->"
    printf '## 约定\n\n- GitLab 模式\n'
    echo "<!-- END:agent-skills-convention -->"
    echo '````'
    echo "<!-- SYNC:claude-block-gitlab END -->"
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
printf 'z\n' > "$TMP/rsmissing/plugins/spec-guard/templates/claude-block-gitlab.md"
printf 'y\n' > "$TMP/rsmissing/plugins/spec-guard/templates/claude-block-local.md"
printf '# README\n没有 SYNC 标记\n' > "$TMP/rsmissing/README.md"
want fail "readme-sync: README 里缺 SYNC 标记 → 报错" python3 "$ROOT/scripts/check-readme-sync.py" "$TMP/rsmissing"

# ── mutation-check.py 的两道安全闸 ──────────────────────────
#   它**在工作区就地改文件**。实测踩过：后台跑的时候另一边跑测试，读到的是
#   被注入变异的 phase-guard.sh，得到一条假失败；而 `git diff` 里躺着的
#   坏指纹算法差点被 commit 出去。两道闸都在跑任何变异之前就退出，所以这组
#   断言很快 —— 免费。
echo ""
echo "═══ mutation-check 的安全闸 ═══"
MC="$ROOT/scripts/mutation-check.py"
LOCK="$ROOT/.mutation-check.lock"

# 锁存在 → 拒跑。（放前面：它不依赖工作区状态，任何时候都测得了）
rm -f "$LOCK"; echo 99999 > "$LOCK"
want fail "mutation-check: 锁存在 → 拒跑" python3 "$MC" --only 不存在的关键词
rm -f "$LOCK"

# 目标文件脏 → 拒跑。真去弄脏一个再还原，不靠模拟。
#
# 前置条件是**三个目标文件全都干净**，不只是被弄脏的那一个：下面那条正向用例
# （干净 + 无锁 → 放行）在任意一个目标脏着的时候都会红，而「改完这三个脚本
# 就跑 validate.sh」恰恰是本仓写在工作流里的动作 —— 那种红是假失败，
# 而假失败会让人学会忽略整套校验（A1）。跳过就明说跳过。
DIRTY="$ROOT/plugins/spec-guard/hooks/spec-digest.py"
MTARGETS=("$ROOT/plugins/spec-guard/hooks/phase-guard.sh" \
          "$ROOT/plugins/spec-guard/hooks/verify-artifacts.sh" "$DIRTY" \
          "$ROOT/plugins/spec-guard/hooks/parallel-execution.py" \
          "$ROOT/plugins/spec-guard/hooks/parallel_execution_lib.py" \
          "$ROOT/plugins/spec-guard/hooks/parallel_worktree_lib.py")
if git -C "$ROOT" diff --quiet HEAD -- "${MTARGETS[@]}" 2>/dev/null; then
  printf '\n# test-checkers 临时弄脏\n' >> "$DIRTY"
  want fail "mutation-check: 目标文件脏 → 拒跑" python3 "$MC" --only 不存在的关键词
  git -C "$ROOT" checkout -- "$DIRTY"
  # 干净 + 无锁 + 匹配不到任何变异体 → 正常走完退 0（正向用例）
  want pass "mutation-check: 干净且无锁 → 放行" python3 "$MC" --only 不存在的关键词
  [ -f "$LOCK" ] && { printf '  ❌ mutation-check: 跑完没清锁\n'; FAIL=$((FAIL+1)); } \
                 || { printf '  ✅ mutation-check: 跑完清掉了锁\n'; PASS=$((PASS+1)); }
else
  printf '  ⏭  mutation-check 用例跳过（变异目标里有未提交改动: %s）—— 跳过不代表通过\n' \
    "$(git -C "$ROOT" diff --name-only HEAD -- "${MTARGETS[@]}" | tr '\n' ' ')"
fi

echo ""
echo "  总计 $PASS 通过 / $FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
