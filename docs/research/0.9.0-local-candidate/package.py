import shutil
import ast, hashlib, io, json, os, stat, subprocess, tarfile
from pathlib import Path
root=Path.cwd(); out=Path('/private/tmp/sg-090-validation')
sha=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
artifact=out/('spec-guard-0.9.0-'+sha[:7]+'-verified'); artifact.mkdir()
paths=['.claude-plugin/marketplace.json','plugins/spec-guard']
blob=subprocess.check_output(['git','archive',sha,*paths])
with tarfile.open(fileobj=io.BytesIO(blob)) as archive:
 for item in archive:
  assert not item.issym() and not item.islnk()
  assert not Path(item.name).is_absolute() and '..' not in Path(item.name).parts
 archive.extractall(artifact)
required=['.claude-plugin/marketplace.json','plugins/spec-guard/.claude-plugin/plugin.json','plugins/spec-guard/.codex-plugin/plugin.json','plugins/spec-guard/manifest.json']
(artifact/'ARTIFACT-MANIFEST.json').write_text(json.dumps({'schemaVersion':1,'artifactKind':'spec-guard-plugin','version':'0.9.0','files':required},indent=2)+'\n')
rows=[]
for entry in subprocess.check_output(['git','ls-tree','-r',sha,'--',*paths],text=True).splitlines():
 meta,name=entry.split('\t'); mode,kind,oid=meta.split(); assert kind=='blob'
 p=artifact/name; expected=subprocess.check_output(['git','cat-file','blob',oid]); assert p.read_bytes()==expected
 # Git records file type and executable bit; normalize archive permission bits.
 p.chmod(int(mode[-3:],8))
 assert stat.S_IMODE(p.stat().st_mode)==int(mode[-3:],8)
 rows.append({'path':name,'gitMode':mode,'sha256':hashlib.sha256(expected).hexdigest()})
actual={str(p.relative_to(artifact)) for p in artifact.rglob('*') if p.is_file()}
assert actual=={r['path'] for r in rows}|{'ARTIFACT-MANIFEST.json'}
assert not (artifact/'.agent').exists() and not (artifact/'spec').exists() and not (artifact/'tasks').exists()
checks=[]
def run(args,env=None):
 p=subprocess.run(args,text=True,capture_output=True,env=env)
 checks.append({'command':args,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
 (out/'package-checks-progress.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2))
 return p
assert run(['python3','scripts/release-package.py','validate',str(artifact),'0.9.0']).returncode==0
fixture=out/'alpha-fixture-verified'; fixture.mkdir()
for d in ['.agent','spec','tasks/alpha','bin']:(fixture/d).mkdir(parents=True)
tree=ast.parse((artifact/'plugins/spec-guard/hooks/test_local_validation.py').read_text())
map_text=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='MAP' for t in n.targets))
(fixture/'spec/CAPABILITY-MAP.md').write_text(map_text)
(fixture/'spec/alpha.md').write_text('# Alpha\n')
(fixture/'tasks/alpha/plan.md').write_text('# Plan\nLocal scope.\n')
for tool in ['git','gh','glab']:
 p=fixture/'bin'/tool;p.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$SG_TEST_CALLS"\nexit 1\n');p.chmod(0o700)
state={'tracker':'github','initiative':{'title':'Local validation reproduction','issue':None,'map':'spec/CAPABILITY-MAP.md'},'issueTypes':False,'modules':{},'activeModule':'alpha','workflowStage':'local-validation'}
for tracker in ['github','gitlab']:
 state['tracker']=tracker
 for case in ['valid','invalid-state','missing-plan']:
  (fixture/'.agent/state.json').write_text('{bad' if case=='invalid-state' else json.dumps(state))
  plan=fixture/'tasks/alpha/plan.md'
  if case=='missing-plan':plan.unlink()
  for label,plugin in [('source',root/'plugins/spec-guard'),('package',artifact/'plugins/spec-guard')]:
   calls=out/(tracker+'-'+case+'-'+label+'.calls');calls.write_text('')
   env=dict(os.environ,CLAUDE_PROJECT_DIR=str(fixture),PLUGIN_ROOT=str(plugin),PYTHONDONTWRITEBYTECODE='1',PATH=str(fixture/'bin')+os.pathsep+os.environ['PATH'],SG_TEST_CALLS=str(calls))
   phase=run(['/bin/bash',str(plugin/'hooks/phase-guard.sh')],env)
   verify=run(['/bin/bash',str(plugin/'hooks/verify-artifacts.sh')],env)
   assert phase.returncode==0
   context=json.loads(phase.stdout)['hookSpecificOutput']['additionalContext']
   assert ('LOCAL_VALIDATION (tracker 尚未激活)' if case=='valid' else 'LOCAL_VALIDATION_INVALID') in context
   assert verify.returncode==(0 if case=='valid' else 1)
   assert '/bin/gh' not in calls.read_text() and '/bin/glab' not in calls.read_text()
   checks[-1]['trackerCalls']=calls.read_text().splitlines()
  if case=='missing-plan':plan.write_text('# Plan\nLocal scope.\n')
history_env=out/'package-history-test-environment'; shutil.copytree(artifact,history_env)
# Historical tests need repository-owned fixtures, outside the distributed package.
history_blob=subprocess.check_output(['git','archive',sha,'spec','tasks/history','.agent/history'])
with tarfile.open(fileobj=io.BytesIO(history_blob)) as archive:archive.extractall(history_env)
for test in ['test_local_validation.py','test_local_context.py','test_artifact_history.py','test_workflow_checkpoints.py']:
 assert run(['python3','-B',str((history_env if test=='test_artifact_history.py' else artifact)/'plugins/spec-guard/hooks'/test)],dict(os.environ,PYTHONDONTWRITEBYTECODE='1')).returncode==0
# Tests must not change distributed content.
for r in rows:assert hashlib.sha256((artifact/r['path']).read_bytes()).hexdigest()==r['sha256']
assert {str(p.relative_to(artifact)) for p in artifact.rglob('*') if p.is_file()}==actual
archive_path=out/(artifact.name+'.tar.gz')
with tarfile.open(archive_path,'w:gz') as archive:archive.add(artifact,arcname=artifact.name)
result={'version':'0.9.0','candidateCommit':sha,'artifactDir':str(artifact),'archive':str(archive_path),'archiveSha256':hashlib.sha256(archive_path.read_bytes()).hexdigest(),'files':rows,'checks':checks,'status':'local candidate content and package behavior verified; no installation or host acceptance'}
(out/'package-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['files','checks']},ensure_ascii=False,indent=2))
