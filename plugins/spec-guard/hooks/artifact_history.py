"""Read-only provenance of top-level specs outside the current capability map."""
import importlib.util
from pathlib import Path
import sys

from capability_map import parse_map

_loader = importlib.util.spec_from_file_location('capability_history', Path(__file__).with_name('capability-history.py'))
history = importlib.util.module_from_spec(_loader)
_loader.loader.exec_module(history)


def classify(project, module_ids):
    root = Path(project).resolve()
    ledger = root / 'spec/CAPABILITY-HISTORY.json'
    if not ledger.exists():
        return [('BAD', 'spec/ 里有能力图上没有的模块: ' + module) for module in module_ids]
    data = history.load(ledger)
    history.verify(data, str(root))
    evidence = {}
    for initiative in data['initiatives']:
        if initiative['events'][-1]['type'] not in history.TERMINAL:
            continue
        for event in initiative['events']:
            checkpoint = event.get('checkpoint')
            if not checkpoint:
                continue
            graph = parse_map(root / checkpoint['map']['path'], validate_graph=False)
            snapshots = {item['id']: item.get('spec') for item in checkpoint['modules']}
            for row in graph.rows:
                evidence.setdefault(row.module_id, []).append(snapshots.get(row.module_id))
    results = []
    for module in module_ids:
        path = root / ('spec/%s.md' % module)
        if root not in path.resolve().parents:
            raise ValueError('spec 路径越过项目根')
        if module not in evidence:
            results.append(('BAD', 'spec/ 里有能力图上没有的模块: ' + module))
            continue
        snapshots = [item for item in evidence[module] if item is not None]
        if not snapshots:
            results.append(('WARN', '历史归属可证，内容未验证: ' + module))
        elif history.digest(path) in {item['sha256'] for item in snapshots}:
            results.append(('OK', '历史内容已验证: ' + module))
        else:
            results.append(('BAD', '历史内容不符: ' + module))
    return results


if __name__ == '__main__':
    try:
        for status, message in classify(sys.argv[1], sys.argv[2:]):
            print(status + '|' + message)
    except (OSError, ValueError, TypeError, KeyError) as error:
        print('BAD|历史证据不可用: ' + str(error).replace('\n', ' '))
        raise SystemExit(1)
