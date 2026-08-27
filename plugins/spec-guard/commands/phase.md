---
description: 查看当前 agent-skills 链路状态
allowed-tools: Bash
---

跑一次链路探测并把结果**格式化**报给用户（不要原样贴 JSON）：

```bash
CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" bash "${CLAUDE_PLUGIN_ROOT}/hooks/phase-guard.sh"
```

解析出 `hookSpecificOutput.additionalContext`，按这个格式呈现：

- 当前阶段
- 各层事实（tracker / spec / plan / GitHub / git）
- 断链项（如有，逐条列出并说明修复方式）
- 建议下一步

**无输出**说明当前项目没装约定，提示用户跑 `/setup-convention`。

> 上面那串 `${CLAUDE_PROJECT_DIR:-…toplevel…}` 不是啰嗦：原先写的是 `$(pwd)`，
> 而 Bash 的工作目录在会话里是会被 `cd` 改掉的。从子目录跑时 hook 找不到
> CLAUDE.md，静默退 0 —— 本命令于是报「没装约定」并劝用户跑
> `/setup-convention`，那一步会在**子目录里**再建一套 spec/ tasks/ .agent/。
> 假警报本身已经违反本插件第一条不变量，它还会引出一次破坏性操作。
