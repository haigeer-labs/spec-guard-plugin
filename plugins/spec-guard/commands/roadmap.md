---
description: 按需查看当前 Initiative 的 agent-skills 工作流路线图
allowed-tools: Bash
---

这是只读查询，不创建或更新 state、task、Issue、PR/MR、binding、worktree、分支或运行进程。
阶段交接、确认或停止前，读取并遵循[共享检查点规则](../references/workflow-checkpoints.md)。

从当前插件根与项目根运行共享路线图脚本：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
python3 -B "${CLAUDE_PLUGIN_ROOT}/hooks/workflow_roadmap.py" --project "$PROJECT"
```

用户明确要求查看活跃能力图的全部模块时，才追加 `--all`。默认只显示当前模块及其直接依赖和后继，
避免把整图带入每次交互。

如脚本报告 Initiative、能力图或当前模块无法唯一确认，原样说明不确定性；不要通过文件新旧、分支名、
模块数量或 Issue 编号猜测。`linked worktree`、分支和 detached HEAD 仅说明代码执行位置，不是模块
绑定、任务领取或并行写入授权。`local-validation` 下不得建议 tracker 同步、领取、绑定或交付。
