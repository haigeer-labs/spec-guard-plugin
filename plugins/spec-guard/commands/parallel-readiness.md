---
description: 基于能力图分析并行开发候选（不创建任务或 worktree）
allowed-tools: Bash
---

这是只读候选分析，不是“安全并行”判定。先定位项目根并运行：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-readiness.py" --project "$PROJECT"
```

报告基线 ref、完整 commit SHA、新鲜度和 `candidate-only` 候选组。明确说明候选组
还必须经过安全审查；不要创建 worktree、分支、子任务、Issue，也不要改动
`.agent/state.json`、`/next` 或 phase hook。

只有用户**明确要求**以最新远端默认分支为基线，且确认允许联网 `git fetch` 后，
才在同一命令末尾追加 `--refresh`。刷新失败时原样报告失败，不得把旧快照说成最新。
