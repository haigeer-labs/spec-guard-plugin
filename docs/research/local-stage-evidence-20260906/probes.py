import json,os,subprocess,shutil
from pathlib import Path
R=Path(__file__).resolve().parent;plugin=R/'candidate/plugins/spec-guard';logs=R/'logs'
f=R/'fixture';env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',CLAUDE_PROJECT_DIR=str(f),PLUGIN_ROOT=str(plugin),PATH=str(f/'bin')+os.pathsep+os.environ['PATH'],SG_TEST_CALLS=str(logs/'direct-gitlab.calls'))
s=json.loads((f/'.agent/state.json').read_text());s['tracker']='gitlab';(f/'.agent/state.json').write_text(json.dumps(s))
p=subprocess.run(['python3','-B',str(plugin/'hooks/gitlab_tracker.py'),'sync','--project',str(f),'--map',str(f/'spec/CAPABILITY-MAP.md'),'--state',str(f/'.agent/state.json')],env=env,capture_output=True,text=True)
(logs/'direct-gitlab.out').write_text(p.stdout+p.stderr);print('gitlab direct',p.returncode,p.stdout,p.stderr)
# Probe only a fresh disposable project; never lifecycle the real repository.
l=R/'lifecycle-local-probe';shutil.copytree(f,l,dirs_exist_ok=True)
p=subprocess.run(['/bin/bash',str(plugin/'hooks/initiative-lifecycle.sh'),'pause','--project',str(l),'--initiative','local-probe'],env=env,capture_output=True,text=True)
cp=json.loads((l/'spec/CAPABILITY-HISTORY.json').read_text())['initiatives'][0]['events'][-1]['checkpoint']
result={'exit':p.returncode,'output':p.stdout+p.stderr,'checkpointModules':cp['modules'],'specStillTopLevel':(l/'spec/alpha.md').exists(),'planStillTopLevel':(l/'tasks/alpha/plan.md').exists()};(logs/'lifecycle-local-probe.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(result)
