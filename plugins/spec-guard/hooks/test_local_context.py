"""Local setup and direct tracker entry points must work without a tracker CLI."""
import json
import os
from pathlib import Path
import subprocess
import unittest

import test_local_validation as fixtures


class LocalContextTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.LocalValidationTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.hooks = Path(__file__).resolve().parent
        self.env = dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root),
                        PLUGIN_ROOT=str(self.hooks.parent), PYTHONDONTWRITEBYTECODE='1',
                        PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
                        SG_TEST_CALLS=str(self.root / 'calls'))

    def setup(self, *args):
        return subprocess.run(['/bin/bash', str(self.hooks / 'setup-convention.sh'),
                               'github', '--local-validation', '--module=alpha',
                               '--title=Local test', *args], env=self.env,
                              capture_output=True, text=True)

    def test_preview_create_and_idempotent_without_remote_calls(self):
        path = self.root / '.agent/state.json'
        path.unlink()
        preview = self.setup()
        self.assertEqual(preview.returncode, 0, preview.stdout + preview.stderr)
        self.assertFalse(path.exists())
        self.assertIn('alpha', preview.stdout)
        created = self.setup('--confirm')
        self.assertEqual(created.returncode, 0, created.stdout + created.stderr)
        state = json.loads(path.read_text())
        self.assertEqual(state['activeModule'], 'alpha')
        self.assertEqual(state['workflowStage'], 'local-validation')
        self.assertEqual(state['modules'], {})
        before = path.read_bytes()
        self.assertEqual(self.setup('--confirm').returncode, 0)
        self.assertEqual(before, path.read_bytes())
        self.assertFalse((self.root / 'calls').exists())

    def test_existing_empty_state_is_updated_but_remote_mapping_is_preserved(self):
        path = self.root / '.agent/state.json'
        state = dict(self.fixture.state)
        state.pop('workflowStage')
        state['activeModule'] = ''
        path.write_text(json.dumps(state))
        self.assertEqual(self.setup('--confirm').returncode, 0)
        state['initiative']['issue'] = 12
        path.write_text(json.dumps(state))
        before = path.read_bytes()
        self.assertNotEqual(self.setup('--confirm').returncode, 0)
        self.assertEqual(before, path.read_bytes())

    def test_invalid_input_disabled_and_dry_run_never_write(self):
        path = self.root / '.agent/state.json'
        before = path.read_bytes()
        self.assertEqual(self.setup('--confirm', '--dry-run').returncode, 0)
        self.assertEqual(before, path.read_bytes())
        (self.root / '.agent/state.json.disabled').write_text('{}')
        self.assertNotEqual(self.setup('--confirm').returncode, 0)
        self.assertEqual(before, path.read_bytes())
        (self.root / '.agent/state.json.disabled').unlink()
        (self.root / 'tasks/alpha/plan.md').unlink()
        self.assertNotEqual(self.setup('--confirm').returncode, 0)
        self.assertEqual(before, path.read_bytes())

    def test_gitlab_setup_and_invalid_state_preserve_bytes(self):
        self.fixture.state['tracker'] = 'gitlab'
        self.fixture.save()
        command = ['/bin/bash', str(self.hooks/'setup-convention.sh'), 'gitlab',
                   '--local-validation', '--module=alpha', '--title=GitLab local', '--confirm']
        p = subprocess.run(command, env=self.env, text=True, capture_output=True)
        self.assertEqual(p.returncode, 0, p.stdout+p.stderr)
        self.assertFalse((self.root/'calls').exists())
        path = self.root/'.agent/state.json'
        for invalid in ('{', '[]', 'null'):
            path.write_text(invalid)
            p = subprocess.run(command, env=self.env, text=True, capture_output=True)
            self.assertNotEqual(p.returncode, 0)
            self.assertEqual(path.read_text(), invalid)

    def test_gitlab_bridge_rejects_local_stage_before_any_cli_call(self):
        p = subprocess.run(['/bin/bash', str(self.hooks / 'gitlab-bridge.sh'),
                            'merge', '--repo', 'test/project', '--iid', '7'],
                           env=self.env, capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('workflowStage', p.stderr)
        self.assertFalse((self.root / 'calls').exists())

    def test_direct_gitlab_sync_rejects_before_auth_even_with_confirm(self):
        self.fixture.state['tracker'] = 'gitlab'
        self.fixture.save()
        p = subprocess.run(['python3', '-B', str(self.hooks / 'gitlab_tracker.py'),
                            'sync', '--project', str(self.root), '--map', str(self.root / 'spec/CAPABILITY-MAP.md'),
                            '--state', str(self.root / '.agent/state.json'), '--confirm'],
                           env=self.env, capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('workflowStage', p.stderr)
        self.assertFalse((self.root / 'calls').exists())


if __name__ == '__main__':
    unittest.main()
