import subprocess,json,os
from pathlib import Path
r=Path(__file__).resolve().parent
checks=['scripts/validate.sh','plugins/spec-guard/hooks/test-phase-guard.sh','plugins/spec-guard/hooks/test-verify-artifacts.sh','plugins/spec-guard/hooks/test-codex-adapter.sh','evals/codex-plugin-smoke.sh --selftest']
results=[]
for check in checks:
 p=subprocess.run(['/bin/bash',*check.split()],cwd=r/'candidate',env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'),text=True,capture_output=True)
 (r/'logs'/('regression-'+Path(check.split()[0]).name+'.out')).write_text(p.stdout+p.stderr)
 results.append({'command':'/bin/bash '+check,'exit':p.returncode,'tail':(p.stdout+p.stderr).splitlines()[-8:]})
 print(json.dumps(results[-1],ensure_ascii=False),flush=True)
 (r/'logs/regressions.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
