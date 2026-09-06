---
description: 暂停、恢复或结束当前 initiative
argument-hint: "<pause|resume|complete|abandon|supersede> --initiative <id> [--dry-run]"
allowed-tools: Bash
---

阶段交接、确认或停止前，读取并遵循[共享检查点规则](../references/workflow-checkpoints.md)；按实际路径预告下一步，已有授权不重复询问。

此操作会复制或恢复 `spec/`、`tasks/` 与 `.agent/state.json`。真实操作前必须先向用户说明影响并取得确认；用户要求预览时，追加 `--dry-run`。

确认后只调用共享入口，不要手动复制、移动或覆盖文件：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/initiative-lifecycle.sh" $ARGUMENTS --project "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
```

原样转述脚本输出。失败时不要删除或覆盖任何用户产物。
