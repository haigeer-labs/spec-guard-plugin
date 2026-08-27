---
description: 从当前项目移除 spec-guard 的约定（保留你的 spec 和 plan 内容）
argument-hint: "[--dry-run] [--keep-state]"
allowed-tools: Bash
---

移除本项目的 spec-guard 约定。**先确认用户真的要移除**，说明会发生什么。

## 执行

直接跑脚本，**不要自己解释执行步骤**——这是插件里唯一的破坏性操作
（删用户 `CLAUDE.md` 里的内容），必须确定性执行：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/teardown-convention.sh" $ARGUMENTS
```

用户说「先看看会删什么」就加 `--dry-run`。

## 它做什么

| 动作 | 说明 |
|---|---|
| 删 `CLAUDE.md` 里 `BEGIN`/`END` 标记之间的内容（含标记） | 标记外一个字节不动 |
| `.agent/state.json` → `.agent/state.json.disabled` | **这一步才是真正的「移除」** |
| 实际跑一遍 `phase-guard.sh` 验证 | 而不是让人相信「无输出即为成功」这句话 |

**不碰**：`spec/`、`tasks/` 里的内容（那是用户的规格和计划），
以及 GitHub 上已创建的 issue。

## 为什么要动 state.json

0.7.0 起 `.agent/state.json` **本身就是 hook 的激活信号**（为 `--no-claude-md`
零足迹模式加的）。只删声明块的话，项目不是「约定被移除」，
而是**变成了零足迹模式** —— 0.7.5 之后 hook 还会每轮注入「先加载 skill」，
比移除前更黏。

改名而不是删除：issue 编号映射删了就找不回来，改回原名即可恢复。

`--keep-state` 保留原名，**hook 会继续激活**，只在确实想切到零足迹模式时用。

## 之后

把脚本输出**原样转述**给用户。退出码 2 表示本项目没启用过约定，什么都没做。
