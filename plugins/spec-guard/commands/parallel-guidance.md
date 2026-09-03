---
description: 生成手动并行开发与汇合指引
allowed-tools: Bash
---

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-guidance.py" --project "$PROJECT"
```

只输出建议；用户自行创建、管理和回收 worker。只有确认联网刷新后才追加 `--refresh`。
