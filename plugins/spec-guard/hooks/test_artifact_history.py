"""Evidence-backed historical specs, and lossless local lifecycle regression."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

import test_local_validation as fixtures


class ArtifactHistoryTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.LocalValidationTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.hooks = Path(__file__).resolve().parent
        self.repo = self.hooks.parents[2]
        for directory in ('spec/history', 'tasks/history', '.agent/history'):
            shutil.copytree(self.repo / directory, self.root / directory)
        shutil.copy2(self.repo / 'spec/CAPABILITY-HISTORY.json', self.root / 'spec/CAPABILITY-HISTORY.json')

    def verify(self):
        return self.fixture.hooks()[1]

    def add(self, name):
        shutil.copy2(self.repo / ('spec/' + name + '.md'), self.root / ('spec/' + name + '.md'))

    def test_snapshot_verified_and_map_only_history_are_distinct(self):
        self.add('history-ledger')
        p = self.verify()
        self.assertEqual(p.returncode, 0, p.stdout)
        self.assertIn('历史内容已验证: history-ledger', p.stdout)

    def test_orphan_and_modified_historical_content_fail(self):
        (self.root / 'spec/orphan.md').write_text('# orphan\n')
        p = self.verify()
        self.assertEqual(p.returncode, 1)
        self.assertIn('能力图上没有的模块: orphan', p.stdout)
        (self.root / 'spec/orphan.md').unlink()
        self.add('history-ledger')
        (self.root / 'spec/history-ledger.md').write_text('# changed\n')
        p = self.verify()
        self.assertEqual(p.returncode, 1)
        self.assertIn('历史内容不符: history-ledger', p.stdout)

    def test_broken_history_cannot_fall_back_to_unverified(self):
        self.add('history-ledger')
        path = self.root / 'spec/history/capability-history/20260903T074408Z-0001/CAPABILITY-MAP.md'
        path.write_text(path.read_text() + '\nchanged\n')
        p = self.verify()
        self.assertEqual(p.returncode, 1)
        self.assertIn('历史证据不可用', p.stdout)

    def test_missing_ledger_and_escaping_history_path_fail(self):
        self.add('history-ledger')
        ledger = self.root/'spec/CAPABILITY-HISTORY.json'
        original = ledger.read_bytes()
        ledger.unlink()
        self.assertEqual(self.verify().returncode, 1)
        data = json.loads(original)
        data['initiatives'][0]['events'][0]['checkpoint']['map']['path'] = '../outside.md'
        ledger.write_text(json.dumps(data))
        result = self.verify()
        self.assertEqual(result.returncode, 1)
        self.assertIn('历史证据不可用', result.stdout)

    def test_current_module_missing_spec_cannot_use_history_exemption(self):
        self.fixture.state['activeModule'] = 'history-ledger'
        self.fixture.save()
        (self.root/'spec/CAPABILITY-MAP.md').write_text(fixtures.MAP.replace('alpha', 'history-ledger'))
        (self.root/'spec/alpha.md').unlink()
        p = self.verify()
        self.assertEqual(p.returncode, 1)
        self.assertIn('当前模块缺少 spec 或 plan', p.stdout)

    def test_invalid_local_lifecycle_keeps_all_current_files(self):
        state = self.root/'.agent/state.json'
        value = json.loads(state.read_text())
        value['workflowStage'] = 'unknown'
        state.write_text(json.dumps(value))
        before = {p: (self.root/p).read_bytes() for p in
                  ('spec/CAPABILITY-MAP.md', 'spec/alpha.md', 'tasks/alpha/plan.md', '.agent/state.json')}
        p = subprocess.run(['/bin/bash', str(self.hooks/'initiative-lifecycle.sh'), 'pause',
                            '--project', str(self.root), '--initiative', 'invalid-local'],
                           capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        for path, contents in before.items():
            self.assertEqual((self.root/path).read_bytes(), contents)
        self.assertFalse((self.root/'spec/history/invalid-local').exists())

    def test_no_map_keeps_legacy_behavior(self):
        self.add('history-ledger')
        (self.root / 'spec/CAPABILITY-MAP.md').unlink()
        (self.root / '.agent/state.json').write_text('{"tracker":"github","activeModule":"","modules":{}}')
        env = dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root),
                   PLUGIN_ROOT=str(self.hooks.parent), PATH=str(self.root/'bin')+os.pathsep+os.environ['PATH'],
                   SG_TEST_CALLS=str(self.root/'calls'), PYTHONDONTWRITEBYTECODE='1')
        p = subprocess.run(['/bin/bash',str(self.hooks/'verify-artifacts.sh')],env=env,text=True,capture_output=True)
        self.assertEqual(p.returncode,0,p.stdout)
        self.assertIn('无能力图，跳过比对',p.stdout)

    def test_pause_resume_local_context_preserves_spec_and_plan(self):
        expected = {name:(self.root/name).read_bytes() for name in
                    ('spec/CAPABILITY-MAP.md','spec/alpha.md','tasks/alpha/plan.md','.agent/state.json')}
        for action in ('pause', 'resume'):
            p = subprocess.run(['/bin/bash',str(self.hooks/'initiative-lifecycle.sh'),action,
                                '--project',str(self.root),'--initiative','alpha-local'],
                               capture_output=True,text=True,env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'))
            self.assertEqual(p.returncode,0,p.stdout+p.stderr)
            if action == 'pause':
                ledger=json.loads((self.root/'spec/CAPABILITY-HISTORY.json').read_text())
                item=next(x for x in ledger['initiatives'] if x['id']=='alpha-local')
                module=item['events'][-1]['checkpoint']['modules'][0]
                self.assertIsNotNone(module['spec'])
                self.assertIsNotNone(module['plan'])
                self.assertFalse((self.root/'spec/alpha.md').exists())
        for name,data in expected.items():
            self.assertEqual(data,(self.root/name).read_bytes())


if __name__ == '__main__':
    unittest.main()
