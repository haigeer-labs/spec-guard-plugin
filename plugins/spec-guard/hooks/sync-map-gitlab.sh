#!/usr/bin/env bash
# 将已评审能力图安全同步到 GitLab。默认只预览，--confirm 才创建 Issue。
set -euo pipefail

confirm=false
[ "${1:-}" = "--confirm" ] && { confirm=true; shift; }
[ "$#" -eq 0 ] || { echo 'usage: sync-map-gitlab.sh [--confirm]' >&2; exit 2; }

hooks="$(cd "$(dirname "$0")" && pwd)"
project="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$project"
command -v glab >/dev/null || { echo '❌ glab 未安装'; exit 1; }
glab auth status >/dev/null || { echo '❌ glab 未认证'; exit 1; }

parsed=$(python3 "$hooks/capability-map.py" spec/CAPABILITY-MAP.md) || {
  printf '%s\n' "$parsed" >&2
  exit 1
}
plan=$(python3 - "$parsed" <<'PY'
import json, pathlib, re, sys
p=pathlib.Path('spec/CAPABILITY-MAP.md')
s=pathlib.Path('.agent/state.json')
if not p.is_file() or not s.is_file(): raise SystemExit('❌ 缺少能力图或 .agent/state.json')
state=json.loads(s.read_text())
if state.get('tracker')!='gitlab': raise SystemExit('❌ 当前不是 gitlab tracker')
text=p.read_text()
if re.search(r'- \[ \]', text): raise SystemExit('❌ 能力图评审记录尚未全部勾选')
title=re.search(r'^# Capability Map:\s*(.+)$', text, re.M)
goal=re.search(r'^## (?:目标|Goal)\s*\n\n(.+?)(?=\n## |\Z)', text, re.M|re.S)
if not title or not goal: raise SystemExit('❌ 能力图缺少标题或目标')
parsed=json.loads(sys.argv[1])
if not parsed.get('ok'): raise SystemExit('❌ 能力图严格校验未通过')
mods=parsed['modules']
if not mods or any(item['id'].startswith('example-') for item in mods):
    raise SystemExit('❌ 能力图没有真实模块或仍含占位模块')
order=parsed['order']
by_id={item['id']: item for item in mods}
print(json.dumps({'title':title.group(1).strip(),'goal':goal.group(1).strip(),'modules':[by_id[item] for item in order]},ensure_ascii=False))
PY
)

repo=$(glab repo view --output json | python3 -c 'import json,sys; print(json.load(sys.stdin)["path_with_namespace"])')
pid=$(glab api "projects/${repo//\//%2F}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
printf '%s' "$plan" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("将同步 initiative: "+d["title"]); [print("  - 模块: "+m["id"]+" — "+m["responsibility"]) for m in d["modules"]]'

if ! "$confirm"; then
  echo '未写入任何远端或本地状态。确认创建请运行：/spec-guard:sync-map --confirm'
  exit 0
fi

initiative_iid=$(glab api -X POST "projects/$pid/issues" -f "title=$(printf '%s' "$plan" | python3 -c 'import json,sys; print(json.load(sys.stdin)["title"])')" -f "description=$(printf '%s' "$plan" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["goal"]+"\n\n<!-- spec-guard-sync:initiative -->")')" | python3 -c 'import json,sys; print(json.load(sys.stdin)["iid"])')

python3 - "$initiative_iid" "$plan" <<'PY'
import json, pathlib, sys
p=pathlib.Path('.agent/state.json'); d=json.loads(p.read_text()); plan=json.loads(sys.argv[2])
d['initiative']['title']=plan['title']; d['initiative']['issue']=int(sys.argv[1])
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
PY

printf '%s' "$plan" | python3 -c 'import json,sys; [print(m["id"]+"\t"+m["responsibility"]) for m in json.load(sys.stdin)["modules"]]' | while IFS=$'\t' read -r mid responsibility; do
  iid=$(glab api -X POST "projects/$pid/issues" -f "title=$mid" -f "description=$responsibility\n\nInitiative: #$initiative_iid\n<!-- spec-guard-sync:module:$mid -->" | python3 -c 'import json,sys; print(json.load(sys.stdin)["iid"])')
  python3 - "$mid" "$iid" "$initiative_iid" <<'PY'
import json, pathlib, sys
p=pathlib.Path('.agent/state.json'); d=json.loads(p.read_text())
d['modules'][sys.argv[1]]={'issue':int(sys.argv[2])}
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
PY
  echo "✅ 创建模块 Issue #${iid}: $mid"
done
python3 - "$plan" <<'PY'
import json, pathlib, sys
p=pathlib.Path('.agent/state.json'); d=json.loads(p.read_text()); plan=json.loads(sys.argv[1])
d['activeModule']=plan['modules'][0]['id']
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
PY
echo "✅ 创建 initiative #${initiative_iid}，并写回 .agent/state.json"
