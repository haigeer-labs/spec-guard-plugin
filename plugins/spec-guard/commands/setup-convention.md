---
description: 在当前项目落地本地多 Spec 目录约定
argument-hint: "[local] [--dry-run] [--replace]"
allowed-tools: Bash
---

执行确定性安装脚本；它只支持本地文件式工作流，不会认证或访问远端 tracker：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/setup-convention.sh" $ARGUMENTS
```

缺省模式为 `local`。`--dry-run` 只预览；`--replace` 仅替换已有受管声明块。
GitHub 与 GitLab tracker 模式已退役，脚本会拒绝它们且不写文件。

成功后原样转述脚本输出，并提醒用户提交受影响的声明块、`spec/`、`tasks/` 和
`.agent/state.json`。旧 remote tracker state 是历史记录，不得用本命令覆盖。
