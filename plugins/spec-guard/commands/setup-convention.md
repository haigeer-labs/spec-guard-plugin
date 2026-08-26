---
description: 在当前项目落地多 Spec 目录约定（首次使用本插件时跑一次）
argument-hint: "[github|local] [--dry-run]"
allowed-tools: Bash
---

在当前项目落地 agent-skills 多 Spec 约定。

## 执行

直接跑脚本，**不要自己解释执行步骤**——写文件是幂等性和安全性要求高的操作，
必须确定性执行：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/setup-convention.sh" $ARGUMENTS
```

`$ARGUMENTS` 缺省时传 `github`。用户说「先看看会做什么」就加 `--dry-run`。

## 之后

把脚本输出**原样转述**给用户（它已经是给人看的格式），然后补充一句：

- 退出码非 0 → 说明前置检查没过，把失败项和修复方法讲清楚，**不要尝试绕过**
- 成功 → 提醒用户 `git add` 那几个文件并提交，队友才能共享约定

## 为什么需要这一步

插件装的是**你这台机器上的工具**（hook、skill、命令）。
但 `CLAUDE.md` 声明块、`spec/`、`.agent/state.json` 必须写进**项目仓库并提交**——
其中 CLAUDE.md 那段声明是激活 agent-skills 内置 External Tracker 分支的开关，
不在仓库里，队友的 `/plan` 还是会写 todo.md。

插件不能替用户往仓库写文件，所以需要这个命令。
