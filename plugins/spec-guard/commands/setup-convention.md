---
description: 在当前项目落地多 Spec 目录约定（首次使用本插件时跑一次）
argument-hint: "[github|local] [--dry-run] [--replace] [--no-claude-md] [--migrate]"
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

### 另外三个开关

| 开关 | 什么时候用 |
|---|---|
| `--replace` | 项目里已有声明块，要**就地升级**到当前模板。只动 `BEGIN`/`END` 之间，标记外一个字节不碰。**不加它时已存在的块原样跳过** |
| `--no-claude-md` | 完全不往 `CLAUDE.md` 写声明块。hook 改由 `.agent/state.json` 存在来激活。**只对 github 模式可用** |
| `--migrate` | 项目已经在没有约定的情况下跑过 `/spec`，`SPEC-<模块>.md` 和能力图散在根上，要迁进 `spec/`。**不加它时只报告不动文件**；目标已存在一律不覆盖并以非零退出 |

`--no-claude-md` 是给 `CLAUDE.md` 已经接近 200 行上限的项目用的（官方建议
target under 200 lines，超了既费 context 又降低 adherence）。

0.7.5 起 hook 会在这个模式下**把触发指令补进每轮注入**（只有零足迹项目付这个
代价）。在此之前这个模式是残的：实测 hook 激活了、状态注入了，但模型全程
没加载 skill —— 状态不等于指令。

**`local --no-claude-md` 会被拒（退出码 2）。** 零足迹靠 `spec-github-bridge`
skill 承接细则，而本地模式没有对应的 skill —— 去掉声明块之后目录约定无处可放，
装了等于没装，还比没装更迷惑（hook 照常报状态，看着像在工作）。

`--migrate` 是三个开关里唯一动用户文件的。移动文件比往 `CLAUDE.md` 追加危险得多，
所以默认只列清单；`--dry-run --migrate` 会把要动的每一对路径打全。
它**不改任何文件正文里的相对链接** —— 那属于越权，而且改错很难发现；
迁完会把仍在引用旧路径的文件列出来，由人决定。

## 之后

把脚本输出**原样转述**给用户（它已经是给人看的格式），然后补充一句：

- 退出码非 0 → 说明前置检查没过，把失败项和修复方法讲清楚，**不要尝试绕过**
- 成功 → 提醒用户 `git add` 那几个文件并提交，队友才能共享约定

## 为什么需要这一步

插件装的是**你这台机器上的工具**（hook、skill、命令）。
但 `CLAUDE.md` 声明块、`spec/`、`.agent/state.json` 必须写进**项目仓库并提交**——
其中 CLAUDE.md 那段声明是激活 agent-skills 内置 External Tracker 分支的开关，
不在仓库里，队友的 `/plan` 还是会写 todo.md。

声明块**只放推导不出来的事实**（路径、tracker 类型、几条硬禁令），
「怎么做」全在 `spec-github-bridge` skill 里 —— skill 按需加载，不占每轮 context。
这是官方对 CLAUDE.md 的明确建议：多步过程应该移进 skill 或 path-scoped rule。

插件不能替用户往仓库写文件，所以需要这个命令。
