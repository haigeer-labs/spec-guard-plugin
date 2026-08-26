---
description: 查看当前 agent-skills 链路状态
allowed-tools: Bash
---

跑一次链路探测并把结果**格式化**报给用户（不要原样贴 JSON）：

```bash
CLAUDE_PROJECT_DIR=$(pwd) bash "${CLAUDE_PLUGIN_ROOT}/hooks/phase-guard.sh"
```

解析出 `hookSpecificOutput.additionalContext`，按这个格式呈现：

- 当前阶段
- 各层事实（tracker / spec / plan / GitHub / git）
- 断链项（如有，逐条列出并说明修复方式）
- 建议下一步

**无输出**说明当前项目没装约定，提示用户跑 `/setup-convention`。
