---
description: 在当前项目落地多 Spec 目录约定（首次使用本插件时跑一次）
argument-hint: "[github|local]"
allowed-tools: Bash, Read, Write, Edit, Glob
---

在当前项目落地 agent-skills 多 Spec 约定。参数 `$ARGUMENTS` 指定模式，缺省为 `github`。

## 为什么需要这一步

插件装的是**你这台机器上的工具**（hook、skill、命令）。
但下面这些必须写进**项目仓库并提交**，否则队友拉下代码后不生效：

- `CLAUDE.md` 的声明块 —— 它是激活 agent-skills 内置 External Tracker 分支的开关
- `spec/` `tasks/` 目录约定
- `.agent/state.json` 进度锚点

所以插件不能替你做，只能引导你做。

---

## 步骤

### 1. 前置检查

先跑这些，把结果报给用户：

```bash
python3 --version
git rev-parse --git-dir 2>/dev/null && echo "in-repo" || echo "not-a-repo"
git remote get-url origin 2>/dev/null || echo "no-remote"
```

`github` 模式额外检查：

```bash
gh --version
gh issue create --help 2>/dev/null | grep -c -- "--parent"
gh auth status 2>&1 | head -3
```

**判定规则**：

| 情况 | 处理 |
|---|---|
| 没有 python3 | 停止。hook 的 JSON 解析依赖它 |
| 不在 git 仓库 | 停止，让用户先 `git init` |
| `gh` < 2.94.0 | **停止**，告知需升级（缺 `--type`/`--parent`/`--blocked-by`） |
| `--parent` grep 结果为 0 | **停止**。版本号可能够但 PATH 里有多个 gh，让用户跑 `type -a gh` |
| `gh` 未认证 | 警告，可继续 |
| 远端不是 GitHub | 警告并**建议改用 local 模式**，等用户确认 |

有阻塞项时**不要继续**，把修复方法说清楚。

### 2. 检查是否已安装

```bash
grep -c "BEGIN:agent-skills-convention" CLAUDE.md 2>/dev/null || echo 0
```

已存在则告诉用户「约定已就位」，只报告当前状态（跑第 6 步）后结束，**不要重复写入**。

### 3. 建目录

```bash
mkdir -p spec tasks .agent
```

### 4. 写 CLAUDE.md 声明块

读取模板：`${CLAUDE_PLUGIN_ROOT}/templates/claude-block-github.md`
（local 模式读 `claude-block-local.md`）

**追加到 CLAUDE.md 末尾**，前后包上标记：

```
<!-- BEGIN:agent-skills-convention -->
（模板内容）
<!-- END:agent-skills-convention -->
```

⚠️ **必须用追加，绝不能覆盖。** 用户的 CLAUDE.md 里有他们自己的项目规范。
文件不存在时才创建新的。

### 5. 写 state.json 和能力图模板

`.agent/state.json`（**已存在则跳过**）：

```json
{
  "tracker": "github",
  "initiative": { "title": "", "issue": null, "map": "spec/CAPABILITY-MAP.md" },
  "modules": {},
  "activeModule": "",
  "updatedAt": ""
}
```

local 模式把 `tracker` 设为 `"none"`。

`spec/CAPABILITY-MAP.md`（**已存在则跳过**）：复制 `${CLAUDE_PLUGIN_ROOT}/templates/CAPABILITY-MAP.md`

### 6. 自检

```bash
CLAUDE_PROJECT_DIR=$(pwd) bash "${CLAUDE_PLUGIN_ROOT}/hooks/phase-guard.sh"
```

应输出含 `hookSpecificOutput` 的 JSON。把里面的「当前阶段」解析出来报给用户。

**无输出**说明 CLAUDE.md 的声明块没写成功，回到第 4 步排查。

### 7. 提示提交

```bash
git status --short CLAUDE.md spec/ .agent/
```

告诉用户：**这些文件要提交进仓库**，队友拉下来才能共享同一套约定。

---

## 输出格式

结束时给一个简洁总结：

```
✅ 约定已落地（模式：github）

  CLAUDE.md          声明块已追加
  spec/              已创建，含能力图模板
  tasks/             已创建
  .agent/state.json  已创建

  当前探测阶段：IDLE

下一步：
  1. 编辑 spec/CAPABILITY-MAP.md 填入模块划分
  2. 人工评审模块边界和 build order（不能跳）
  3. /sync-map 把能力图落成 GitHub Issue
  4. /planning 为第一个模块拆解任务

⚠️ 记得把 CLAUDE.md、spec/、.agent/ 提交进仓库
```

---

## 不要做的事

- **不要覆盖已有的 CLAUDE.md**
- **不要覆盖已有的 state.json 或 CAPABILITY-MAP.md**（用户可能已经填过内容）
- **不要在前置检查失败时硬着头皮继续**
- **不要自动 git commit** —— 让用户自己看过再提交
- **不要同时写 github 和 local 两种声明块** —— 它们互斥，`/planning` 会精神分裂
