import ast, hashlib, json, os, shutil, subprocess
from pathlib import Path
R=Path(__file__).resolve().parent
candidate=R/'candidate/plugins/spec-guard'
tree=ast.parse((candidate/'hooks/test_local_validation.py').read_text())
MAP=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='MAP' for t in n.targets))
roots={'baseline':R/'baseline/plugins/spec-guard','candidate':candidate,'codex-installed':Path.home()/'.codex/plugins/cache/spec-guard-marketplace/spec-guard/0.8.0','claude-installed':Path.home()/'.claude/plugins/cache/spec-guard-marketplace/spec-guard/0.7.51'}
logs=R/'logs';logs.mkdir(exist_ok=True)
fixture=R/'fixture';fixture.mkdir(exist_ok=True)
for d in ['.agent','spec','tasks/alpha','bin']: (fixture/d).mkdir(parents=True,exist_ok=True)
for name in ['git','gh','glab']:
 p=fixture/'bin'/name;p.write_text('#!/bin/sh\nprintf "%s %s\\n" "$0" "$*" >> "$SG_TEST_CALLS"\nexit 1\n');p.chmod(0o700)
state={'tracker':'github','initiative':{'title':'Local validation reproduction','issue':None,'map':'spec/CAPABILITY-MAP.md'},'issueTypes':False,'modules':{},'activeModule':'alpha','workflowStage':'local-validation'}
(fixture/'spec/CAPABILITY-MAP.md').write_text(MAP);(fixture/'spec/alpha.md').write_text('# Alpha\n');(fixture/'tasks/alpha/plan.md').write_text('# Plan\nLocal scope.\n')
results=[]
def run(label,plugin,project,case):
 for hook in ['phase-guard.sh','verify-artifacts.sh']:
  key=f'{case}-{label}-{hook}';calls=logs/(key+'.calls');calls.write_text('')
  env=dict(os.environ,CLAUDE_PROJECT_DIR=str(project),PLUGIN_ROOT=str(plugin),PYTHONDONTWRITEBYTECODE='1',PATH=str(fixture/'bin')+os.pathsep+os.environ['PATH'],SG_TEST_CALLS=str(calls))
  p=subprocess.run(['/bin/bash',str(plugin/'hooks'/hook)],env=env,text=True,capture_output=True,timeout=30)
  (logs/(key+'.out')).write_text(p.stdout);(logs/(key+'.err')).write_text(p.stderr)
  row={'case':case,'version':label,'hook':hook,'exit':p.returncode,'calls':calls.read_text().splitlines()};results.append(row)
  print(case,label,hook,p.returncode)
for tracker in ['github','gitlab']:
 state['tracker']=tracker;(fixture/'.agent/state.json').write_text(json.dumps(state))
 for label,plugin in roots.items():run(label,plugin,fixture,'local-'+tracker)
state['tracker']='github';(fixture/'.agent/state.json').write_text(json.dumps(state))
# Historical combination is copied, never moved or cleaned in the source checkout.
hist=R/'historical';coexist=R/'coexist';shutil.copytree(hist,coexist,dirs_exist_ok=True)
(coexist/'AGENTS.md').write_text('<!-- BEGIN:spec-guard-codex-convention -->\n<!-- END:spec-guard-codex-convention -->\n')
for label in ['baseline','candidate']:run(label,roots[label],coexist,'historical-six-map')
arch=R/'archived';arch.mkdir(exist_ok=True)
for path in ['spec','tasks','.agent']:
 src=Path.cwd()/path
 if src.exists():shutil.copytree(src,arch/path,dirs_exist_ok=True)
(arch/'AGENTS.md').write_text((coexist/'AGENTS.md').read_text())
for label in ['baseline','candidate']:run(label,roots[label],arch,'archived-no-map')
# Minimal new graph plus the same proven historical artifacts, then a true orphan.
minimal=R/'history-with-alpha';shutil.copytree(arch,minimal,dirs_exist_ok=True)
(minimal/'spec/CAPABILITY-MAP.md').write_text(MAP);(minimal/'spec/alpha.md').write_text('# Alpha\n');(minimal/'tasks/alpha').mkdir(parents=True,exist_ok=True);(minimal/'tasks/alpha/plan.md').write_text('# Plan\nLocal scope.\n');(minimal/'.agent/state.json').write_text(json.dumps(state))
run('candidate',candidate,minimal,'history-with-alpha')
(minimal/'spec/orphan.md').write_text('# Unowned\n');run('candidate',candidate,minimal,'history-with-orphan')
ledger=json.loads((hist/'spec/CAPABILITY-HISTORY.json').read_text());ownership=[]
for p in sorted((arch/'spec').glob('*.md')):
 digest=hashlib.sha256(p.read_bytes()).hexdigest();matches=[]
 for initiative in ledger['initiatives']:
  for event in initiative['events']:
   cp=event.get('checkpoint',{})
   for mod in cp.get('modules',[]):
    a=mod.get('spec')
    if mod['id']==p.stem and a:
     saved=hist/a['path']; matches.append({'initiative':initiative['id'],'event':event['type'],'checkpoint':cp['id'],'path':a['path'],'topMatchesLedger':digest==a['sha256'],'snapshotMatchesLedger':saved.exists() and hashlib.sha256(saved.read_bytes()).hexdigest()==a['sha256']})
 ownership.append({'file':p.name,'sha256':digest,'matches':matches})
(logs/'ownership.json').write_text(json.dumps(ownership,ensure_ascii=False,indent=2))
def inventory(root):return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.pyc'}
invs={k:inventory(v) for k,v in roots.items()};diffs={}
for label,inv in invs.items():
 diffs[label]={other:[p for p in sorted(set(inv)|set(otherinv)) if inv.get(p)!=otherinv.get(p)] for other,otherinv in invs.items() if label!=other}
(logs/'plugin-content.json').write_text(json.dumps({'inventories':invs,'differences':diffs},indent=2));(logs/'results.json').write_text(json.dumps(results,indent=2))
print('ownership',[(x['file'],len(x['matches']),all(m['topMatchesLedger'] and m['snapshotMatchesLedger'] for m in x['matches'])) for x in ownership])
