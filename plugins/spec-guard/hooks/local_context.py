"""Explicit local state writer used only by setup-convention, never by hooks."""
import argparse
import json
import os
from pathlib import Path
import tempfile

from local_validation import validate_state


def configure(root, tracker, module, title, confirm=False):
    root = Path(root)
    directory = root / '.agent'
    path = directory / 'state.json'
    if directory.is_symlink() or path.is_symlink():
        raise ValueError('本地 state 路径不能是符号链接')
    if (directory / 'state.json.disabled').exists():
        raise ValueError('存在 disabled state，请先明确恢复原上下文')
    original = path.read_bytes() if path.exists() else None
    state = json.loads(original) if original is not None else {
        'tracker': tracker, 'initiative': {'issue': None},
        'issueTypes': False, 'modules': {},
    }
    if not isinstance(state, dict) or not isinstance(state.get('initiative'), dict):
        raise ValueError('state 必须包含 initiative 对象')
    if (state.get('tracker') != tracker or state.get('modules') != {} or
            state['initiative'].get('issue') is not None):
        raise ValueError('拒绝覆盖 tracker 或已有远端映射')
    if 'workflowStage' in state and state['workflowStage'] != 'local-validation':
        raise ValueError('拒绝覆盖未知 workflowStage')
    state.update(activeModule=module, workflowStage='local-validation')
    state['initiative'].update(title=title, issue=None, map='spec/CAPABILITY-MAP.md')
    status, message = validate_state(root, state)
    if status != 'valid':
        raise ValueError(message)
    print('本地上下文预览：%s' % path)
    print(json.dumps({'before': json.loads(original) if original is not None else None,
                      'after': state}, ensure_ascii=False, indent=2))
    if not confirm:
        print('未写入；确认本次上下文后使用相同参数加 --confirm。下一步仅写 state 并验证，不激活 tracker。')
        return
    if original is not None and json.loads(original) == state:
        print('上下文已一致，无需写入。')
        return
    directory.mkdir(exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.local-state-', dir=directory)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            json.dump(state, handle, ensure_ascii=False, indent=2)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        current = path.read_bytes() if path.exists() else None
        if current != original:
            raise ValueError('state 已变化，请重新预览')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print('已写入并验证本地上下文；tracker 尚未激活。按当前 plan 的已授权检查点继续。')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tracker', choices=('github', 'gitlab'))
    parser.add_argument('--local-validation', action='store_true', required=True)
    parser.add_argument('--module', required=True)
    parser.add_argument('--title', required=True)
    parser.add_argument('--host', choices=('claude', 'codex'))
    parser.add_argument('--confirm', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        configure(os.environ.get('CLAUDE_PROJECT_DIR', os.getcwd()), args.tracker,
                  args.module, args.title, args.confirm and not args.dry_run)
        return 0
    except (OSError, ValueError) as error:
        print('本地上下文未写入：%s' % error)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
