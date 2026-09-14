#!/usr/bin/env bash
# initiative-lifecycle.sh 的 pause 安全性回归。
set -uo pipefail

HOOKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIFECYCLE="$HOOKDIR/initiative-lifecycle.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }
has_glob() { compgen -G "$1" >/dev/null; }

PROJECT="$TMP/project"
mkdir -p "$PROJECT/spec" "$PROJECT/tasks/payment-api" "$PROJECT/tasks/ledger" "$PROJECT/.agent"
printf '# Capability Map: Payment\n\n## 目标\n\npay\n\n## 模块\n\n| Module id | Responsibility | Depends on |\n| --- | --- | --- |\n| payment-api | API | — |\n| ledger | Ledger entries | payment-api |\n' > "$PROJECT/spec/CAPABILITY-MAP.md"
printf '# Spec\n' > "$PROJECT/spec/payment-api.md"
printf '# Ledger\n' > "$PROJECT/spec/ledger.md"
printf '# Plan\n' > "$PROJECT/tasks/payment-api/plan.md"
printf '# Ledger plan\n' > "$PROJECT/tasks/ledger/plan.md"
printf '{"activeModule":"payment-api","modules":{"payment-api":{"issue":101},"ledger":{"issue":102}}}\n' > "$PROJECT/.agent/state.json"

echo "═══ Initiative lifecycle regression ═══"
if [ -f "$LIFECYCLE" ] && "$LIFECYCLE" pause --project "$PROJECT" --initiative payment-v2 --dry-run >/dev/null 2>&1 \
  && [ -f "$PROJECT/spec/CAPABILITY-MAP.md" ] && [ -f "$PROJECT/spec/payment-api.md" ] \
  && [ -f "$PROJECT/tasks/payment-api/plan.md" ] && [ -f "$PROJECT/.agent/state.json" ]; then
  ok "正：pause --dry-run 只报告，不修改当前产物"
else
  bad "正：pause --dry-run 只报告，不修改当前产物"
fi

if [ -f "$LIFECYCLE" ] && "$LIFECYCLE" pause --project "$PROJECT" --initiative payment-v2 >/dev/null 2>&1 \
  && [ ! -f "$PROJECT/spec/CAPABILITY-MAP.md" ] && [ ! -f "$PROJECT/.agent/state.json" ] \
  && [ ! -f "$PROJECT/spec/payment-api.md" ] && [ ! -f "$PROJECT/spec/ledger.md" ] \
  && [ ! -f "$PROJECT/tasks/payment-api/plan.md" ] && [ ! -f "$PROJECT/tasks/ledger/plan.md" ] \
  && [ -f "$PROJECT/spec/CAPABILITY-HISTORY.json" ] \
  && [ "$(python3 "$HOOKDIR/capability-history.py" status "$PROJECT/spec/CAPABILITY-HISTORY.json" payment-v2)" = paused ] \
  && has_glob "$PROJECT/spec/history/payment-v2/*/CAPABILITY-MAP.md" \
  && has_glob "$PROJECT/spec/history/payment-v2/*/payment-api.md" \
  && has_glob "$PROJECT/spec/history/payment-v2/*/ledger.md" \
  && has_glob "$PROJECT/tasks/history/payment-v2/*/payment-api/plan.md" \
  && has_glob "$PROJECT/tasks/history/payment-v2/*/ledger/plan.md" \
  && has_glob "$PROJECT/.agent/history/payment-v2/*/state.json" \
  && python3 - "$PROJECT/spec/CAPABILITY-HISTORY.json" <<'PY'
import json
import sys

ledger = json.load(open(sys.argv[1], encoding="utf-8"))
modules = ledger["initiatives"][0]["events"][-1]["checkpoint"]["modules"]
assert [(module["id"], module["responsibility"], module["dependsOn"], module["status"])
        for module in modules] == [
    ("payment-api", "API", [], "unknown"),
    ("ledger", "Ledger entries", ["payment-api"], "unknown"),
]
PY
then
  ok "正：账本不存在时 pause 自动建账并归档当前工作区"
else
  bad "正：账本不存在时 pause 自动建账并归档当前工作区"
fi

HISTORY="$HOOKDIR/capability-history.py"
CREATED="$TMP/created.json"
printf '%s\n' '{"id":"payment-v2","title":"Payment v2","events":[{"type":"created","at":"2026-09-02T09:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/payment-v2/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}}]}' > "$CREATED"

TERMINAL_PROJECT="$TMP/terminal-project"
mkdir -p "$TERMINAL_PROJECT/spec" "$TERMINAL_PROJECT/.agent"
: > "$TERMINAL_PROJECT/spec/CAPABILITY-MAP.md"
printf '{}' > "$TERMINAL_PROJECT/.agent/state.json"
if "$LIFECYCLE" complete --project "$TERMINAL_PROJECT" --initiative payment-v2 >/dev/null 2>&1 \
  && [ ! -f "$TERMINAL_PROJECT/spec/CAPABILITY-MAP.md" ] \
  && [ "$(python3 "$HISTORY" status "$TERMINAL_PROJECT/spec/CAPABILITY-HISTORY.json" payment-v2)" = completed ] \
  && has_glob "$TERMINAL_PROJECT/spec/history/payment-v2/*/CAPABILITY-MAP.md"; then
  ok "正：账本不存在时 complete 自动建账、写入终态 checkpoint 后清理当前工作区"
else
  bad "正：账本不存在时 complete 自动建账、写入终态 checkpoint 后清理当前工作区"
fi

EXISTING_LEDGER_PROJECT="$TMP/existing-ledger-project"
mkdir -p "$EXISTING_LEDGER_PROJECT/spec" "$EXISTING_LEDGER_PROJECT/.agent"
printf '# Current map\n' > "$EXISTING_LEDGER_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"activeModule":null,"modules":{}}\n' > "$EXISTING_LEDGER_PROJECT/.agent/state.json"
EXISTING_CREATED="$TMP/existing-created.json"
printf '%s\n' '{"id":"older-initiative","title":"Older initiative","events":[{"type":"created","at":"2026-09-02T09:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/older-initiative/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}},{"type":"completed","at":"2026-09-02T10:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/older-initiative/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}}]}' > "$EXISTING_CREATED"
python3 "$HISTORY" create "$EXISTING_LEDGER_PROJECT/spec/CAPABILITY-HISTORY.json" "$EXISTING_CREATED" >/dev/null 2>&1
if "$LIFECYCLE" complete --project "$EXISTING_LEDGER_PROJECT" --initiative new-initiative >/dev/null 2>&1 \
  && [ ! -f "$EXISTING_LEDGER_PROJECT/spec/CAPABILITY-MAP.md" ] \
  && [ "$(python3 "$HISTORY" status "$EXISTING_LEDGER_PROJECT/spec/CAPABILITY-HISTORY.json" older-initiative)" = completed ] \
  && [ "$(python3 "$HISTORY" status "$EXISTING_LEDGER_PROJECT/spec/CAPABILITY-HISTORY.json" new-initiative)" = completed ] \
  && has_glob "$EXISTING_LEDGER_PROJECT/spec/history/new-initiative/*/CAPABILITY-MAP.md"; then
  ok "正：已有其他 initiative 的账本可登记并完成新的 initiative"
else
  bad "正：已有其他 initiative 的账本可登记并完成新的 initiative"
fi

RESUME_PROJECT="$TMP/resume-project"
RESUME_CHECKPOINT="20260904T090000Z-0002"
mkdir -p "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT" \
  "$RESUME_PROJECT/tasks/history/payment-v2/$RESUME_CHECKPOINT/payment-api" \
  "$RESUME_PROJECT/.agent/history/payment-v2/$RESUME_CHECKPOINT"
printf '# Restored map\n' > "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT/CAPABILITY-MAP.md"
printf '# Restored spec\n' > "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT/payment-api.md"
printf '# Restored plan\n' > "$RESUME_PROJECT/tasks/history/payment-v2/$RESUME_CHECKPOINT/payment-api/plan.md"
printf '{"activeModule":"payment-api"}\n' > "$RESUME_PROJECT/.agent/history/payment-v2/$RESUME_CHECKPOINT/state.json"
MAP_SHA="$(shasum -a 256 "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT/CAPABILITY-MAP.md" | awk '{print $1}')"
SPEC_SHA="$(shasum -a 256 "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT/payment-api.md" | awk '{print $1}')"
PLAN_SHA="$(shasum -a 256 "$RESUME_PROJECT/tasks/history/payment-v2/$RESUME_CHECKPOINT/payment-api/plan.md" | awk '{print $1}')"
STATE_SHA="$(shasum -a 256 "$RESUME_PROJECT/.agent/history/payment-v2/$RESUME_CHECKPOINT/state.json" | awk '{print $1}')"
RESUME_CREATED="$TMP/resume-created.json"
RESUME_PAUSED="$TMP/resume-paused.json"
printf '%s\n' '{"id":"payment-v2","title":"Payment v2","events":[{"type":"created","at":"2026-09-02T09:00:00Z","checkpoint":{"id":"20260902T090000Z-0001","map":{"path":"spec/history/payment-v2/20260902T090000Z-0001/CAPABILITY-MAP.md","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"modules":[]}}]}' > "$RESUME_CREATED"
printf '%s\n' "{\"type\":\"paused\",\"at\":\"2026-09-04T09:00:00Z\",\"checkpoint\":{\"id\":\"$RESUME_CHECKPOINT\",\"map\":{\"path\":\"spec/history/payment-v2/$RESUME_CHECKPOINT/CAPABILITY-MAP.md\",\"sha256\":\"$MAP_SHA\"},\"state\":{\"path\":\".agent/history/payment-v2/$RESUME_CHECKPOINT/state.json\",\"sha256\":\"$STATE_SHA\"},\"modules\":[{\"id\":\"payment-api\",\"responsibility\":\"Payment API\",\"dependsOn\":[],\"status\":\"in-progress\",\"issue\":101,\"spec\":{\"path\":\"spec/history/payment-v2/$RESUME_CHECKPOINT/payment-api.md\",\"sha256\":\"$SPEC_SHA\"},\"plan\":{\"path\":\"tasks/history/payment-v2/$RESUME_CHECKPOINT/payment-api/plan.md\",\"sha256\":\"$PLAN_SHA\"}}]}}" > "$RESUME_PAUSED"
python3 "$HISTORY" create "$RESUME_PROJECT/spec/CAPABILITY-HISTORY.json" "$RESUME_CREATED" >/dev/null 2>&1 || true
python3 "$HISTORY" append "$RESUME_PROJECT/spec/CAPABILITY-HISTORY.json" payment-v2 "$RESUME_PAUSED" >/dev/null 2>&1 || true
if "$LIFECYCLE" resume --project "$RESUME_PROJECT" --initiative payment-v2 >/dev/null 2>&1 \
  && [ "$(cat "$RESUME_PROJECT/spec/CAPABILITY-MAP.md")" = '# Restored map' ] \
  && [ "$(cat "$RESUME_PROJECT/spec/payment-api.md")" = '# Restored spec' ] \
  && [ "$(cat "$RESUME_PROJECT/tasks/payment-api/plan.md")" = '# Restored plan' ] \
  && [ "$(cat "$RESUME_PROJECT/.agent/state.json")" = '{"activeModule":"payment-api"}' ] \
  && [ "$(python3 "$HISTORY" status "$RESUME_PROJECT/spec/CAPABILITY-HISTORY.json" payment-v2)" = resumed ]; then
  ok "正：resume 恢复最后 paused checkpoint 的全部当前产物"
else
  bad "正：resume 恢复最后 paused checkpoint 的全部当前产物"
fi

printf 'tampered map\n' > "$RESUME_PROJECT/spec/history/payment-v2/$RESUME_CHECKPOINT/CAPABILITY-MAP.md"
printf 'keep current\n' > "$RESUME_PROJECT/spec/CAPABILITY-MAP.md"
if ! "$LIFECYCLE" resume --project "$RESUME_PROJECT" --initiative payment-v2 >/dev/null 2>&1 \
  && [ "$(cat "$RESUME_PROJECT/spec/CAPABILITY-MAP.md")" = 'keep current' ]; then
  ok "反：损坏 checkpoint 时 resume 不覆盖当前工作区"
else
  bad "反：损坏 checkpoint 时 resume 不覆盖当前工作区"
fi

# lifecycle 的模块集合必须来自能力图，而不是 state 的任意 key。否则 `../`
# 会在归档后半段走进 rm，删除用户的项目文件。
ESCAPE_PROJECT="$TMP/escape-project"
mkdir -p "$ESCAPE_PROJECT/spec" "$ESCAPE_PROJECT/tasks/alpha" "$ESCAPE_PROJECT/.agent"
printf '# Capability Map: Escape\n\n## 目标\n\nescape\n\n## 模块\n\n| Module id | Responsibility | Depends on |\n| --- | --- | --- |\n| alpha | Alpha | — |\n' > "$ESCAPE_PROJECT/spec/CAPABILITY-MAP.md"
printf '# Alpha\n' > "$ESCAPE_PROJECT/spec/alpha.md"
printf '# Plan\n' > "$ESCAPE_PROJECT/tasks/alpha/plan.md"
printf 'must survive\n' > "$ESCAPE_PROJECT/sentinel.md"
printf '{"activeModule":"alpha","modules":{"../sentinel":{"issue":1}}}\n' > "$ESCAPE_PROJECT/.agent/state.json"
if ! "$LIFECYCLE" complete --project "$ESCAPE_PROJECT" --initiative escape-test >/dev/null 2>&1 \
  && [ "$(cat "$ESCAPE_PROJECT/sentinel.md")" = 'must survive' ] \
  && [ -f "$ESCAPE_PROJECT/spec/CAPABILITY-MAP.md" ] \
  && [ ! -d "$ESCAPE_PROJECT/spec/history/escape-test" ]; then
  ok "反：state 含越界 module id → 拒绝且不删文件、不建归档"
else
  bad "反：越界 module id 被生命周期接受或留下写入"
fi

# initiative 本身也是路径片段；拒绝必须发生在 mkdir/cp 之前。
PATH_PROJECT="$TMP/path-project"
mkdir -p "$PATH_PROJECT/spec" "$PATH_PROJECT/tasks/alpha" "$PATH_PROJECT/.agent" "$TMP/outside"
printf '# Capability Map: Path\n\n## 目标\n\npath\n\n## 模块\n\n| Module id | Responsibility | Depends on |\n| --- | --- | --- |\n| alpha | Alpha | — |\n' > "$PATH_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"activeModule":"alpha","modules":{"alpha":{"issue":1}}}\n' > "$PATH_PROJECT/.agent/state.json"
if ! "$LIFECYCLE" complete --project "$PATH_PROJECT" --initiative ../../../outside >/dev/null 2>&1 \
  && [ -z "$(find "$TMP/outside" -mindepth 1 -print -quit)" ] \
  && [ -f "$PATH_PROJECT/spec/CAPABILITY-MAP.md" ]; then
  ok "反：越界 initiative → 拒绝且项目外零残留"
else
  bad "反：越界 initiative 可写入项目外路径"
fi

# 清理阶段失败时，不能先把 completed/paused 事件记进账本，更不能留下半个 checkpoint。
CLEANUP_PROJECT="$TMP/cleanup-failure-project"
mkdir -p "$CLEANUP_PROJECT/spec" "$CLEANUP_PROJECT/tasks/alpha" "$CLEANUP_PROJECT/tasks/beta" "$CLEANUP_PROJECT/.agent" "$TMP/fake-rm-bin"
printf '# Capability Map: Cleanup\n\n## 模块\n\n| Module id | Responsibility | Depends on |\n| --- | --- | --- |\n| alpha | Alpha | — |\n| beta | Beta | alpha |\n' > "$CLEANUP_PROJECT/spec/CAPABILITY-MAP.md"
printf '# Alpha\n' > "$CLEANUP_PROJECT/spec/alpha.md"
printf '# Beta\n' > "$CLEANUP_PROJECT/spec/beta.md"
printf '# Plan\n' > "$CLEANUP_PROJECT/tasks/alpha/plan.md"
printf '# Beta plan\n' > "$CLEANUP_PROJECT/tasks/beta/plan.md"
# tracker=github + 有效 GitHub origin：归档快照会被改写（写入 repository），
# 恢复用的必须是改写前的原始字节，不能是那份被改过的快照。
printf '{"tracker":"github","activeModule":"alpha","modules":{"alpha":{"issue":1},"beta":{"issue":2}},"initiative":{"title":"x","issue":1}}\n' > "$CLEANUP_PROJECT/.agent/state.json"
git -C "$CLEANUP_PROJECT" init -q
git -C "$CLEANUP_PROJECT" remote add origin https://github.com/Cleanup/Origin.git
cp "$CLEANUP_PROJECT/.agent/state.json" "$TMP/cleanup-original-state.json"
cat > "$TMP/fake-rm-bin/rm" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in */spec/beta.md) exit 1 ;; esac
done
exec /bin/rm "$@"
STUB
chmod +x "$TMP/fake-rm-bin/rm"
CLEANUP_OUTPUT="$(PATH="$TMP/fake-rm-bin:$PATH" \
    "$LIFECYCLE" pause --project "$CLEANUP_PROJECT" --initiative cleanup-failure 2>&1)"
CLEANUP_STATUS=$?
if [ "$CLEANUP_STATUS" -ne 0 ] \
  && [ -f "$CLEANUP_PROJECT/spec/CAPABILITY-MAP.md" ] \
  && [ -f "$CLEANUP_PROJECT/spec/alpha.md" ] \
  && [ -f "$CLEANUP_PROJECT/spec/beta.md" ] \
  && [ -f "$CLEANUP_PROJECT/tasks/alpha/plan.md" ] \
  && [ -f "$CLEANUP_PROJECT/tasks/beta/plan.md" ] \
  && [ -f "$CLEANUP_PROJECT/.agent/state.json" ] \
  && [ ! -f "$CLEANUP_PROJECT/spec/CAPABILITY-HISTORY.json" ] \
  && ! has_glob "$CLEANUP_PROJECT/spec/history/cleanup-failure/*/CAPABILITY-MAP.md"; then
  ok "反：清理失败时恢复当前产物且不记录事件或残留 checkpoint"
else
  bad "反：清理失败后留下半归档或错误 lifecycle 状态"
  printf '    cleanup status=%s output=%s\n' "$CLEANUP_STATUS" "$CLEANUP_OUTPUT"
fi

# 恢复的 .agent/state.json 必须与改写前的原始字节完全相同 —— 不能是归档
# 过程中被写入 repository 字段之后的那份快照。
if cmp -s "$CLEANUP_PROJECT/.agent/state.json" "$TMP/cleanup-original-state.json"; then
  ok "反：清理失败后恢复的 state.json 与原始字节完全一致（cmp）"
else
  bad "反：清理失败后恢复的 state.json 字节被篡改（应与改写前完全一致）"
fi
if [ "$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
print("repository" in (d.get("initiative") or {}))' "$CLEANUP_PROJECT/.agent/state.json")" = "False" ]; then
  ok "反：清理失败后恢复的 state.json 没有 repository 字段"
else
  bad "反：清理失败后恢复的 state.json 意外带有 repository 字段（快照改写泄漏到了当前产物）"
fi

# GitHub 归档快照记录仓库身份（Spec: archive-github-repository.md）。
snapshot_repository() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("initiative") or {}).get("repository", ""))' "$1"
}
latest_snapshot() {
  ls -d "$1"/*/state.json 2>/dev/null | sort | tail -1
}
ledger_state_sha() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["initiatives"][0]["events"][-1]["checkpoint"]["state"]["sha256"])' "$1"
}

GH1_PROJECT="$TMP/gh-ssh-alias-project"
mkdir -p "$GH1_PROJECT/spec" "$GH1_PROJECT/.agent"
printf '# Map\n' > "$GH1_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"github","activeModule":null,"modules":{},"initiative":{"title":"x","issue":1}}' > "$GH1_PROJECT/.agent/state.json"
git -C "$GH1_PROJECT" init -q
git -C "$GH1_PROJECT" remote add origin git@github-alias:Owner/Repo.git
if "$LIFECYCLE" complete --project "$GH1_PROJECT" --initiative gh-ssh-alias >/dev/null 2>&1; then
  GH1_SNAPSHOT="$(latest_snapshot "$GH1_PROJECT/.agent/history/gh-ssh-alias")"
  GH1_SHA="$(shasum -a 256 "$GH1_SNAPSHOT" | awk '{print $1}')"
  if [ -n "$GH1_SNAPSHOT" ] \
    && [ "$(snapshot_repository "$GH1_SNAPSHOT")" = "Owner/Repo" ] \
    && [ "$(ledger_state_sha "$GH1_PROJECT/spec/CAPABILITY-HISTORY.json")" = "$GH1_SHA" ]; then
    ok "正：tracker=github + SSH host 别名 origin → 快照记录 owner/repo，账本 sha256 与快照一致"
  else
    bad "正：tracker=github + SSH host 别名 origin → 快照记录 owner/repo，账本 sha256 与快照一致"
  fi
else
  bad "正：tracker=github + SSH host 别名 origin → 快照记录 owner/repo，账本 sha256 与快照一致"
fi

GH2_PROJECT="$TMP/gh-https-project"
mkdir -p "$GH2_PROJECT/spec" "$GH2_PROJECT/.agent"
printf '# Map\n' > "$GH2_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"github","activeModule":null,"modules":{},"initiative":{"title":"x","issue":1}}' > "$GH2_PROJECT/.agent/state.json"
git -C "$GH2_PROJECT" init -q
git -C "$GH2_PROJECT" remote add origin https://github.com/Owner/Repo
if "$LIFECYCLE" complete --project "$GH2_PROJECT" --initiative gh-https >/dev/null 2>&1; then
  GH2_SNAPSHOT="$(latest_snapshot "$GH2_PROJECT/.agent/history/gh-https")"
  if [ -n "$GH2_SNAPSHOT" ] && [ "$(snapshot_repository "$GH2_SNAPSHOT")" = "Owner/Repo" ]; then
    ok "正：tracker=github + https origin（无 .git 后缀）→ 快照记录 owner/repo"
  else
    bad "正：tracker=github + https origin（无 .git 后缀）→ 快照记录 owner/repo"
  fi
else
  bad "正：tracker=github + https origin（无 .git 后缀）→ 快照记录 owner/repo"
fi

GH3_PROJECT="$TMP/gh-no-origin-project"
mkdir -p "$GH3_PROJECT/spec" "$GH3_PROJECT/.agent"
printf '# Map\n' > "$GH3_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"github","activeModule":null,"modules":{},"initiative":{"title":"x","issue":1}}' > "$GH3_PROJECT/.agent/state.json"
git -C "$GH3_PROJECT" init -q
GH3_OUTPUT="$("$LIFECYCLE" complete --project "$GH3_PROJECT" --initiative gh-no-origin 2>&1)"
GH3_STATUS=$?
GH3_SNAPSHOT="$(latest_snapshot "$GH3_PROJECT/.agent/history/gh-no-origin")"
if [ "$GH3_STATUS" -eq 0 ] && [ -n "$GH3_SNAPSHOT" ] \
  && [ "$(snapshot_repository "$GH3_SNAPSHOT")" = "" ] \
  && grep -q '提示：无法从 origin 解析 GitHub 仓库' <<<"$GH3_OUTPUT"; then
  ok "正：tracker=github + 无 origin → 归档成功、无 repository 字段、打印提示"
else
  bad "正：tracker=github + 无 origin → 归档成功、无 repository 字段、打印提示"
  printf '    status=%s output=%s\n' "$GH3_STATUS" "$GH3_OUTPUT"
fi

GH4_PROJECT="$TMP/gh-non-github-origin-project"
mkdir -p "$GH4_PROJECT/spec" "$GH4_PROJECT/.agent"
printf '# Map\n' > "$GH4_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"github","activeModule":null,"modules":{},"initiative":{"title":"x","issue":1}}' > "$GH4_PROJECT/.agent/state.json"
git -C "$GH4_PROJECT" init -q
git -C "$GH4_PROJECT" remote add origin https://gitlab.com/o/r.git
if "$LIFECYCLE" complete --project "$GH4_PROJECT" --initiative gh-non-github >/dev/null 2>&1; then
  GH4_SNAPSHOT="$(latest_snapshot "$GH4_PROJECT/.agent/history/gh-non-github")"
  if [ -n "$GH4_SNAPSHOT" ] && [ "$(snapshot_repository "$GH4_SNAPSHOT")" = "" ]; then
    ok "正：tracker=github + 非 GitHub origin → 无 repository 字段"
  else
    bad "正：tracker=github + 非 GitHub origin → 无 repository 字段"
  fi
else
  bad "正：tracker=github + 非 GitHub origin → 无 repository 字段"
fi

GH5_PROJECT="$TMP/gh-alias-no-user-project"
mkdir -p "$GH5_PROJECT/spec" "$GH5_PROJECT/.agent"
printf '# Map\n' > "$GH5_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"github","activeModule":null,"modules":{},"initiative":{"title":"x","issue":1}}' > "$GH5_PROJECT/.agent/state.json"
git -C "$GH5_PROJECT" init -q
git -C "$GH5_PROJECT" remote add origin github-alias:Owner/Repo.git
if "$LIFECYCLE" complete --project "$GH5_PROJECT" --initiative gh-alias-no-user >/dev/null 2>&1; then
  GH5_SNAPSHOT="$(latest_snapshot "$GH5_PROJECT/.agent/history/gh-alias-no-user")"
  if [ -n "$GH5_SNAPSHOT" ] && [ "$(snapshot_repository "$GH5_SNAPSHOT")" = "Owner/Repo" ]; then
    ok "正：tracker=github + scp 别名 origin（无 user）→ 快照记录 owner/repo"
  else
    bad "正：tracker=github + scp 别名 origin（无 user）→ 快照记录 owner/repo"
  fi
else
  bad "正：tracker=github + scp 别名 origin（无 user）→ 快照记录 owner/repo"
fi

# repository 字段非字符串（如账本迁移留下的数字）不是「合法值」，必须
# 视同缺失，重新从当前 origin 解析 —— 不能因 isinstance 检查外的疏漏把
# 一个坏类型悄悄当成「已有合法记录」而跳过写回。
NONSTR_PROJECT="$TMP/gh-nonstring-repository-project"
mkdir -p "$NONSTR_PROJECT/spec" "$NONSTR_PROJECT/.agent"
printf '# Map\n' > "$NONSTR_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"github","activeModule":null,"modules":{},"initiative":{"title":"x","issue":1,"repository":123}}' > "$NONSTR_PROJECT/.agent/state.json"
git -C "$NONSTR_PROJECT" init -q
git -C "$NONSTR_PROJECT" remote add origin https://github.com/Owner/Repo.git
if "$LIFECYCLE" complete --project "$NONSTR_PROJECT" --initiative gh-nonstring-repository >/dev/null 2>&1; then
  NONSTR_SNAPSHOT="$(latest_snapshot "$NONSTR_PROJECT/.agent/history/gh-nonstring-repository")"
  if [ -n "$NONSTR_SNAPSHOT" ] && [ "$(snapshot_repository "$NONSTR_SNAPSHOT")" = "Owner/Repo" ]; then
    ok "正：state 里 repository 是非字符串 → 视同缺失，从当前 origin 重新解析"
  else
    bad "正：state 里 repository 是非字符串 → 视同缺失，从当前 origin 重新解析"
  fi
else
  bad "正：state 里 repository 是非字符串 → 视同缺失，从当前 origin 重新解析"
fi

# pause → resume → 改 origin → complete：resume 恢复的是 FIRST（pause）
# checkpoint 里原样保存的当前产物；那个 checkpoint 自己的 state.json（在
# .agent/history 下）此后不应再被写。后面这次 complete 建的是全新的
# checkpoint 目录，不会碰旧目录，但这里用字节级 sha256 直接把「不应变」
# 钉死为可回归的断言。
ROUNDTRIP_BYTES_PROJECT="$TMP/roundtrip-bytes-project"
mkdir -p "$ROUNDTRIP_BYTES_PROJECT/spec" "$ROUNDTRIP_BYTES_PROJECT/.agent"
printf '# Map\n' > "$ROUNDTRIP_BYTES_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"github","activeModule":null,"modules":{},"initiative":{"title":"x","issue":1}}' > "$ROUNDTRIP_BYTES_PROJECT/.agent/state.json"
git -C "$ROUNDTRIP_BYTES_PROJECT" init -q
git -C "$ROUNDTRIP_BYTES_PROJECT" remote add origin https://github.com/First/Checkpoint.git
RTB_LABEL="正：pause → resume → 改 origin → complete，首个（pause）checkpoint 的 state.json 字节不变"
if "$LIFECYCLE" pause --project "$ROUNDTRIP_BYTES_PROJECT" --initiative roundtrip-bytes >/dev/null 2>&1; then
  RTB_FIRST_SNAPSHOT="$(latest_snapshot "$ROUNDTRIP_BYTES_PROJECT/.agent/history/roundtrip-bytes")"
  RTB_FIRST_SHA_BEFORE="$(shasum -a 256 "$RTB_FIRST_SNAPSHOT" | awk '{print $1}')"
  if "$LIFECYCLE" resume --project "$ROUNDTRIP_BYTES_PROJECT" --initiative roundtrip-bytes >/dev/null 2>&1 \
    && git -C "$ROUNDTRIP_BYTES_PROJECT" remote set-url origin git@github-alias:Second/Checkpoint.git \
    && sleep 1 \
    && "$LIFECYCLE" complete --project "$ROUNDTRIP_BYTES_PROJECT" --initiative roundtrip-bytes >/dev/null 2>&1; then
    RTB_FIRST_SHA_AFTER="$(shasum -a 256 "$RTB_FIRST_SNAPSHOT" | awk '{print $1}')"
    if [ "$RTB_FIRST_SHA_BEFORE" = "$RTB_FIRST_SHA_AFTER" ]; then
      ok "$RTB_LABEL"
    else
      bad "$RTB_LABEL"
    fi
  else
    bad "$RTB_LABEL"
  fi
else
  bad "$RTB_LABEL"
fi

NONE_PROJECT="$TMP/none-tracker-project"
mkdir -p "$NONE_PROJECT/spec" "$NONE_PROJECT/.agent"
printf '# Map\n' > "$NONE_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"none","activeModule":null,"modules":{}}' > "$NONE_PROJECT/.agent/state.json"
cp "$NONE_PROJECT/.agent/state.json" "$TMP/none-tracker-original-state.json"
git -C "$NONE_PROJECT" init -q
git -C "$NONE_PROJECT" remote add origin git@github.com:Owner/Repo.git
if "$LIFECYCLE" complete --project "$NONE_PROJECT" --initiative none-tracker >/dev/null 2>&1; then
  NONE_SNAPSHOT="$(latest_snapshot "$NONE_PROJECT/.agent/history/none-tracker")"
  if [ -n "$NONE_SNAPSHOT" ] && cmp -s "$NONE_SNAPSHOT" "$TMP/none-tracker-original-state.json"; then
    ok "正：tracker=none → 快照字节与原始 state 完全一致（不改写）"
  else
    bad "正：tracker=none → 快照字节与原始 state 完全一致（不改写）"
  fi
else
  bad "正：tracker=none → 快照字节与原始 state 完全一致（不改写）"
fi

KEEP_PROJECT="$TMP/keep-repo-project"
mkdir -p "$KEEP_PROJECT/spec" "$KEEP_PROJECT/.agent"
printf '# Map\n' > "$KEEP_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"github","activeModule":null,"modules":{},"initiative":{"title":"x","issue":1,"repository":"Old/Repo"}}' > "$KEEP_PROJECT/.agent/state.json"
git -C "$KEEP_PROJECT" init -q
git -C "$KEEP_PROJECT" remote add origin git@github-alias:New/Repo.git
if "$LIFECYCLE" complete --project "$KEEP_PROJECT" --initiative keep-repo >/dev/null 2>&1; then
  KEEP_SNAPSHOT="$(latest_snapshot "$KEEP_PROJECT/.agent/history/keep-repo")"
  if [ -n "$KEEP_SNAPSHOT" ] && [ "$(snapshot_repository "$KEEP_SNAPSHOT")" = "Old/Repo" ]; then
    ok "正：state 已带合法 repository → 保留原值，忽略当前 origin"
  else
    bad "正：state 已带合法 repository → 保留原值，忽略当前 origin"
  fi
else
  bad "正：state 已带合法 repository → 保留原值，忽略当前 origin"
fi

RT_PROJECT="$TMP/roundtrip-project"
mkdir -p "$RT_PROJECT/spec" "$RT_PROJECT/.agent"
printf '# Map\n' > "$RT_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"github","activeModule":null,"modules":{},"initiative":{"title":"x","issue":1}}' > "$RT_PROJECT/.agent/state.json"
git -C "$RT_PROJECT" init -q
git -C "$RT_PROJECT" remote add origin https://github.com/Round/Trip.git
# resume 之后改 origin：若 resume 丢了字段，complete 会从新 origin 解析出 New/Repo。
RT_LABEL="正：pause → resume → 改 origin → complete，最终快照仍是首次记录的 repository"
if "$LIFECYCLE" pause --project "$RT_PROJECT" --initiative roundtrip >/dev/null 2>&1 \
  && "$LIFECYCLE" resume --project "$RT_PROJECT" --initiative roundtrip >/dev/null 2>&1 \
  && git -C "$RT_PROJECT" remote set-url origin git@github-alias:New/Repo.git \
  && sleep 1 \
  && "$LIFECYCLE" complete --project "$RT_PROJECT" --initiative roundtrip >/dev/null 2>&1; then
  RT_SNAPSHOT="$(latest_snapshot "$RT_PROJECT/.agent/history/roundtrip")"
  if [ -n "$RT_SNAPSHOT" ] && [ "$(snapshot_repository "$RT_SNAPSHOT")" = "Round/Trip" ] \
    && [ "$(python3 "$HISTORY" status "$RT_PROJECT/spec/CAPABILITY-HISTORY.json" roundtrip)" = completed ]; then
    ok "$RT_LABEL"
  else
    bad "$RT_LABEL"
  fi
else
  bad "$RT_LABEL"
fi

# 机器上没有 git：仓库身份不可得，但归档不能因此失败（spec: Never fail an archive）。
# 只把脚本实际用到的命令链接进 PATH，刻意不放 git。
NOGIT_BIN="$TMP/nogit-bin"; mkdir -p "$NOGIT_BIN"
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$NOGIT_BIN/python3"
for tool in bash awk cp date dirname mkdir mktemp rm sed shasum cat mv ls sort tail head grep tr basename touch chmod env; do
  tool_path="$(command -v "$tool" 2>/dev/null || true)"
  [ -n "$tool_path" ] && ln -s "$tool_path" "$NOGIT_BIN/$tool"
done
NOGIT_PROJECT="$TMP/nogit-project"
mkdir -p "$NOGIT_PROJECT/spec" "$NOGIT_PROJECT/.agent"
printf '# Map\n' > "$NOGIT_PROJECT/spec/CAPABILITY-MAP.md"
printf '{"tracker":"github","activeModule":null,"modules":{},"initiative":{"title":"x","issue":1}}' > "$NOGIT_PROJECT/.agent/state.json"
NOGIT_OUTPUT="$(PATH="$NOGIT_BIN" "$LIFECYCLE" complete --project "$NOGIT_PROJECT" --initiative nogit 2>&1)"
NOGIT_STATUS=$?
NOGIT_SNAPSHOT="$(latest_snapshot "$NOGIT_PROJECT/.agent/history/nogit")"
if [ "$NOGIT_STATUS" -eq 0 ] && [ -n "$NOGIT_SNAPSHOT" ] \
  && [ "$(snapshot_repository "$NOGIT_SNAPSHOT")" = "" ] \
  && grep -q '提示：无法从 origin 解析 GitHub 仓库' <<<"$NOGIT_OUTPUT"; then
  ok "正：机器上没有 git → 归档成功、无 repository 字段、打印提示"
else
  bad "正：机器上没有 git → 归档成功、无 repository 字段、打印提示"
  printf '    status=%s output=%s\n' "$NOGIT_STATUS" "$NOGIT_OUTPUT"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
