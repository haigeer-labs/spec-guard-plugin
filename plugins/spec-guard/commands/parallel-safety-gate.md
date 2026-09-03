---
description: 审查并行候选的显式边界冲突（不自动执行）
allowed-tools: Bash
---

默认只审查本地已知基线：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-safety-gate.py" --project "$PROJECT"
```

`manual-parallel-eligible` 只表示可以由用户确认后手动启动隔离 worktree；缺失或冲突
声明必须串行或人工审查。不得创建任务、worktree、分支、Issue 或修改 state。只有用户
明确确认联网刷新后才追加 `--refresh`。
