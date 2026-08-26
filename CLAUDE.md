# CLAUDE.md

给在**本仓库**（spec-guard 插件本身）工作的 AI agent 用。

> ⚠️ **作用域**：本文件配置的是开发 spec-guard 这个插件的 agent。
> 它**不是**给使用者复制到自己项目里的——使用者要的是
> `plugins/spec-guard/templates/claude-block-*.md`，由 `/setup-convention` 写入。

> ⚠️ **自引用陷阱**：本文件刻意**不包含**那个会激活 phase-guard hook 的标题
> 字符串。如果在本仓库写入它，hook 会在插件自己的仓库上激活，报一堆无意义的断链。
> 修改本文件时不要粘贴 `templates/claude-block-github.md` 的内容。

---

## 这是什么

一个 Claude Code 插件，给 `addyosmani/agent-skills` 补三样东西：

1. 多模块 Spec 目录约定
2. GitHub Issue 打通
3. 链路断裂检测（UserPromptSubmit hook）

设计依据见 `docs/design.md`，**改动前先读它**——里面每条结论都对应上游源码的
具体行号，不是拍脑袋定的。

---

## 目录

```
.claude-plugin/marketplace.json         ← marketplace 清单（路径不能改）
plugins/spec-guard/
├── .claude-plugin/plugin.json          ← 插件清单（路径不能改）
├── commands/*.md                       ← slash 命令
├── hooks/
│   ├── hooks.json                      ← hook 注册
│   ├── phase-guard.sh                  ← 核心：状态探测
│   └── test-phase-guard.sh             ← 回归测试
├── skills/spec-github-bridge/SKILL.md
└── templates/                          ← 由 /setup-convention 写入用户项目
docs/design.md                          ← 需求与设计
scripts/
├── validate.sh                         ← 仓库完整性校验
└── check-manifests.py
```

---

## 改动前必读

### phase-guard.sh 的三条不可违反的性质

1. **默认不生效** —— 检查用户项目的 CLAUDE.md 是否含约定标题，没有就静默 `exit 0`。
   装了插件不能污染其他项目。
2. **探测失败就降级，不误报** —— `gh` 不可用、远端不是 GitHub、不是 git 仓库，
   任何一种都不能报假断链。**假断链比不报断链危害大得多。**
3. **不越权** —— 只注入事实和建议，断链处理必须「先说明、得到确认后再执行」。

改动时如果动摇了任何一条，先想清楚为什么。

### 无外部依赖

`phase-guard.sh` 只能依赖 `bash` / `git` / `python3`。
**不要引入 `jq` 硬依赖** —— 早期版本踩过，缺 `jq` 时 `activeModule` 静默读不出来，
一路误判。现在用 `jread()` 做 python3 兜底。

---

## 工作流

```bash
# 改完必跑这两个
bash scripts/validate.sh
bash plugins/spec-guard/hooks/test-phase-guard.sh
```

改了 `phase-guard.sh` 的状态机逻辑，**必须同步加测试用例**。
当前 15 个断言：phase-guard 12 个（空仓库 / 各阶段 / 三种 tracker 模式 / 静默退出 /
不崩溃）+ setup-convention 3 个（dry-run 零写入 / 不覆盖用户内容 / 幂等）。

---

## 发版

```
1. 改 plugins/spec-guard/.claude-plugin/plugin.json 的 version
2. 更新 CHANGELOG.md（含「已知限制」章节）
3. bash scripts/validate.sh && bash plugins/spec-guard/hooks/test-phase-guard.sh
4. git tag v<version>
5. push
```

**版本号不升，使用者收不到更新** —— Claude Code 靠 `plugin.json` 的 `version`
判断是否拉取新版。

---

## 禁止

- **不要 fork 或 vendored 上游 agent-skills 的任何文件** —— 所有适配走约定和本插件
- **不要在 phase-guard.sh 里做写操作** —— 它是探测器，只读
- **不要在本仓库的 CLAUDE.md 里写激活字符串** —— 见顶部的自引用陷阱
- **不要用 `jq` 作为硬依赖**
- **不要写 `$VAR` 紧跟多字节字符** —— 如 `"…#$ISSUE）"`。macOS 自带 bash 3.2 会把
  全角括号的首字节吃进变量名，配上 `set -u` 直接致命退出，而 hook 失败是静默的。
  一律写 `${VAR}`。`scripts/check-bash32.py` 会拦，CI 也加了 macOS matrix
- **不要在 hook 里输出非 JSON** —— 宿主会拒绝，且失败是静默的
- **不要给 hook 加长耗时操作** —— 它在每次用户发言前跑，超过 1s 就会有体感

---

## 调试 hook

```bash
# 直接跑，看原始输出
CLAUDE_PROJECT_DIR=/path/to/test-project bash plugins/spec-guard/hooks/phase-guard.sh

# 解析出可读内容
CLAUDE_PROJECT_DIR=/path/to/test-project bash plugins/spec-guard/hooks/phase-guard.sh \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])"
```

**无输出**的两种可能：目标项目的 CLAUDE.md 没有约定标题（正常），或脚本报错
（用 `bash -x` 排查）。
