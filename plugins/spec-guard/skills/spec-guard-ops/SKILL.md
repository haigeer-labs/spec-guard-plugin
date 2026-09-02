---
name: spec-guard-ops
description: 在 Codex 中执行 spec-guard 的约定落地、状态探测、产物校验与清理操作。
---

## 公共环境

所有确定性脚本操作都从 Codex 已启用插件清单和项目根解析路径：

```bash
CODEX_PLUGINS="$(codex plugin list --available --json 2>/dev/null || true)"
ROOT="$(printf '%s' "$CODEX_PLUGINS" | python3 -c '
import json, sys
try:
    plugins = json.load(sys.stdin).get("installed", [])
except (ValueError, TypeError):
    raise SystemExit
for plugin in plugins:
    if plugin.get("name") == "spec-guard" and plugin.get("installed") and plugin.get("enabled"):
        print(plugin["source"]["path"])
        break
')"
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

若 `ROOT` 为空，停止并说明 spec-guard 未安装或未启用；不要猜测用户目录，也不要假定 hook
环境变量会传递给 agent shell。

## `setup`

在当前项目写入 Codex 约定时，执行：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/setup-convention.sh" github --host=codex
```

用户要求本地 tracker 时，将 `github` 改为 `local`。需要预览时加 `--dry-run`；已有
Codex 标记而要求升级时加 `--replace`。将脚本输出原样转述，成功后提醒提交 `AGENTS.md`、
`.agent/state.json` 与新建目录。

## `phase`

只读地查看当前阶段：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/phase-guard.sh"
```

解析结果后说明阶段、事实、断链项和建议下一步；无输出表示项目尚未启用约定，不要创建文件。

## `verify`

只读地校验已落产物：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/verify-artifacts.sh"
```

如有违规，说明原因与修复方式，得到用户确认后才改动项目；退出码 2 表示尚未启用约定。

## `verify-history`

历史证据校验为只读操作，调用共享脚本：

```bash
/bin/bash "$ROOT/hooks/verify-history.sh" "$PROJECT"
```

无账本时报告“未验证”；orphan 或篡改证据时报告失败，不自动删除任何文件。

## `teardown`

这是破坏性操作。先明确告知会删除 `AGENTS.md` 中完整的 Codex 约定块，并要求用户确认。
只有确认后才执行：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/teardown-convention.sh" --host=codex
```

原样转述脚本结果；不要删除标记外内容或手动修改 state。

## `lifecycle`

用户请求暂停、恢复或结束 initiative 时，先说明真实操作会复制或恢复当前
`spec/`、`tasks/` 与 `.agent/state.json`，并明确要求确认。仅在确认后调用共享脚本：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/initiative-lifecycle.sh" <pause|resume|complete|abandon|supersede> --project "$PROJECT" --initiative <id>
```

用户只要求预览时追加 `--dry-run`；不要自行复制、移动或覆盖这些文件。

## `sync-map`

加载 `spec-guard:spec-github-bridge`，并仅按该 skill 的“操作一：能力图落库”执行。
它可能创建 GitHub issue，必须遵循其中的前置检查、确认与增量写回规则。

## `next`

加载 `spec-guard:spec-github-bridge`，并仅按该 skill 的“操作三：取下一个任务”执行。
不要复制或自行改写 issue 筛选逻辑。

## `deliver`

加载 `spec-guard:spec-github-bridge`，并仅按该 skill 的“操作四：交付（模块级 PR）”执行。
不要在此 skill 中复制 GitHub 或交付流程。
