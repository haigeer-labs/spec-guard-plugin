"""Check discoverability of the single checkpoint contract, not model behavior."""
from pathlib import Path
import unittest


class CheckpointContractTests(unittest.TestCase):
    def setUp(self):
        self.plugin = Path(__file__).resolve().parents[1]

    def test_command_and_skill_references_resolve_to_one_contract(self):
        entries = [self.plugin/'commands'/ (name+'.md') for name in
                   ('phase','verify-artifacts','setup-convention','sync-map','next','deliver','initiative-lifecycle','bind-workspace')]
        entries += [self.plugin/'skills'/name/'SKILL.md' for name in
                    ('spec-github-bridge','spec-gitlab-bridge','spec-guard-ops')]
        target = self.plugin/'references/workflow-checkpoints.md'
        self.assertTrue(target.is_file())
        for path in entries:
            with self.subTest(path=path):
                self.assertIn('references/workflow-checkpoints.md',path.read_text())

    def test_all_templates_load_contract_and_rule_covers_stop_conditions(self):
        for path in (self.plugin/'templates').glob('*-block-*.md'):
            self.assertIn('检查点',path.read_text(),str(path))
        text=(self.plugin/'references/workflow-checkpoints.md').read_text()
        for scenario in ('设计 → 计划','计划 → 实现','实现 → 验证','验证失败','交付前','权限被拒绝','结果未知','取消或暂停'):
            self.assertIn(scenario,text)
        for rule in ('不重复','最近一次','失效','并行','无需确认'):
            self.assertIn(rule,text)


if __name__ == '__main__':
    unittest.main()
