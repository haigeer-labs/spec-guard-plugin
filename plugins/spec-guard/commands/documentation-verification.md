---
description: 只读核验模块声明的文档交付状态，不把它当作内容或代码验证
allowed-tools: Bash, Read, Write
---

先选择模块并查询：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MODULE="<module-id>"
python3 -B "${CLAUDE_PLUGIN_ROOT}/hooks/documentation_verification.py" \
  --project "$PROJECT" --module "$MODULE" --format json
```

`absent` 表示项目未启用基线，应静默跳过；`attention` 表示待决、未声明 outcome 或延后事项，属于提醒而非阻断；`ready` 仅表示所有需交付项已**声明** delivered；`invalid` 表示已有表格结构无效。不得把 `ready` 解释为文档内容、发布状态或代码符合度已经验证。

根据用户提供的真实交付事实预览 `Documentation outcome` 表；只有用户明确确认后才修改 Plan 或任何业务文档。不得扫描代码、Git diff、时间戳或权威文档正文来猜测文档状态。
