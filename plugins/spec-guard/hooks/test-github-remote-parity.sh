#!/usr/bin/env bash
# github_remote.py（Python）与 phase-guard.sh / verify-artifacts.sh 里各自的
# remote_host/is_github_remote（bash）必须对同一组 remote URL 给出相同判定。
#
# 三份实现互相独立维护 —— Python 那份供 initiative-lifecycle.sh 的归档写入
# 用，两个 bash 版供 hook 的每轮状态注入 / 按需体检用。三者判据分叉是
# 「归档记了 owner/repo，hook 却判它不是 GitHub 远端」这类断链的直接成因。
#
# 只读比对，不修改任何共享判据：分歧就是分歧，交给人判断要不要改，
# 不能在这里悄悄「对齐」。
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }

# 从共享判据文件里精确抽出两个函数定义，原样 eval 到独立子 shell 里执行 ——
# 不复制、不改写，抽出来的就是当前那两个 hook 实际在跑的那份代码。
extract_functions() {  # $1=源文件
  sed -n '/^remote_host() {/,/^}/p; /^is_github_remote() {/,/^}/p' "$1"
}

bash_is_github_remote() {  # $1=源文件  $2=url
  local src="$1" url="$2"
  ( eval "$(extract_functions "$src")"; is_github_remote "$url" )
}

python_is_github_remote() {  # $1=url
  python3 -c '
import sys
sys.path.insert(0, sys.argv[2])
from github_remote import is_github_remote
sys.exit(0 if is_github_remote(sys.argv[1]) else 1)
' "$1" "$HOOKDIR"
}

# 共享表：覆盖 https / ssh:// 带端口 / user@host:path / 无 user 的 scp 别名 /
# 大写 host / 路径里含 github 的 GitLab host / 尾随斜杠 / 大写 .GIT /
# github 不在 host 开头（ssh.github.com、www.github.com）—— 否则把「host 含
# github」误改成「host 以 github 开头」时，整张表仍会全部通过。
# 每行：url|expect（yes=是 GitHub 远端，no=不是）
TABLE='https://github.com/Owner/Repo.git|yes
ssh://git@github.com:22/Owner/Repo.git|yes
git@github.com:Owner/Repo.git|yes
git@github-collab:Owner/Repo.git|yes
github-alias:Owner/Repo.git|yes
git@ssh.github.com:Owner/Repo.git|yes
https://www.github.com/Owner/Repo.git|yes
https://GITHUB.COM/Owner/Repo.git|no
https://gitlab.com/me/github-tools.git|no
https://github.com/Owner/Repo/|yes
git@github.com:Owner/Repo.GIT|yes
https://gitlab.com/o/r.git|no
git@gitlab.com:o/r.git|no
/tmp/repo|no'

echo "═══ github_remote 判定一致性（Python / phase-guard.sh / verify-artifacts.sh）═══"

while IFS='|' read -r URL EXPECT; do
  [ -n "$URL" ] || continue

  PY_RC=0; python_is_github_remote "$URL" >/dev/null 2>&1 || PY_RC=$?
  PG_RC=0; bash_is_github_remote "$HOOKDIR/phase-guard.sh" "$URL" >/dev/null 2>&1 || PG_RC=$?
  VA_RC=0; bash_is_github_remote "$HOOKDIR/verify-artifacts.sh" "$URL" >/dev/null 2>&1 || VA_RC=$?

  PY_GOT=$([ "$PY_RC" -eq 0 ] && echo yes || echo no)
  PG_GOT=$([ "$PG_RC" -eq 0 ] && echo yes || echo no)
  VA_GOT=$([ "$VA_RC" -eq 0 ] && echo yes || echo no)

  if [ "$PY_GOT" = "$PG_GOT" ] && [ "$PG_GOT" = "$VA_GOT" ] && [ "$PY_GOT" = "$EXPECT" ]; then
    ok "$URL → 三份实现一致（${PY_GOT}）"
  else
    bad "$URL → 分歧: python=$PY_GOT phase-guard=$PG_GOT verify-artifacts=${VA_GOT}（期望 ${EXPECT}）"
  fi
done <<<"$TABLE"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
