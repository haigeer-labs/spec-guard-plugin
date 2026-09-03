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

用户要求 GitLab tracker 时，将 `github` 改为 `gitlab`；要求本地 tracker 时改为 `local`。需要预览时加 `--dry-run`；已有
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

## `history-migration`

迁移预览是只读操作：

```bash
python3 "$ROOT/hooks/history-migration.py" preview "$PROJECT"
```

执行导入前，必须说明它会创建新的历史 checkpoint 与账本，并取得用户明确确认；确认后才调用：

```bash
python3 "$ROOT/hooks/history-migration.py" import --confirm "$PROJECT"
```

不要自行写入或修改旧 spec、plan、state 与 Git 历史。

## `parallel-readiness`

这是只读的并行开发候选分析：它只根据能力图依赖层和精确的默认分支 SHA 给出
`candidate-only` 组，**不等于安全可并行**，也不会创建 worktree、分支、宿主子任务、
Issue 或更改 `.agent/state.json`、`/next`、生命周期和 hook。

默认使用本地已知的远端跟踪快照（报告会标明新鲜度未验证）：

```bash
python3 "$ROOT/hooks/parallel-readiness.py" --project "$PROJECT"
```

只有用户明确要求最新远端默认分支，且已完成用户确认允许联网刷新后，才追加
`--refresh`：

```bash
python3 "$ROOT/hooks/parallel-readiness.py" --project "$PROJECT" --refresh
```

刷新失败时报告失败；不要回退成“最新”结论。无论哪种结果，都提示用户下一步需由
parallel-safety-gate 审查路径、接口、迁移、配置和测试资源冲突。

## `parallel-safety-gate`

这是显式、只读的安全门；`manual-parallel-eligible` 不会自动创建或回收任何 worktree、
任务、分支、Issue 或子代理，也不改 state、`/next` 或 hook：

```bash
python3 "$ROOT/hooks/parallel-safety-gate.py" --project "$PROJECT"
```

只有用户明确要求并确认联网刷新后才追加 `--refresh`。缺失边界声明或任意冲突必须报告
`needs-review`/`sequential-required`，不得推荐自动并行。

## `parallel-guidance`

只为 `manual-parallel-eligible` 输出人工 worker 命名与汇合清单，不创建、管理或回收
worktree、任务、分支或 Issue：

```bash
python3 "$ROOT/hooks/parallel-guidance.py" --project "$PROJECT"
```

用户明确确认联网刷新后才追加 `--refresh`；其余结果仅说明为何应人工审查或串行。

## `parallel-subagent-preflight`

这是 **Codex 专用的只读预检**，不是并行代码实现。先运行 safety gate：

```bash
python3 "$ROOT/hooks/parallel-safety-gate.py" --project "$PROJECT"
```

只在报告对目标候选组返回 `manual-parallel-eligible`、当前会话提供原生 `spawn_agent`
工具、且用户**明确确认**要开启子智能体预检时，父会话才可以为每个模块调用一次
`spawn_agent`。每个任务名使用 `sg-preflight-<module-id>`，提示首行使用
`SG 自动并行预检｜<module-id>`，并要求子智能体：

- 只读检查模块 spec、`Parallel Boundary`、依赖、实施风险与测试范围；
- 不修改文件，不运行会写入的测试，不提交、不推送；
- 不运行 `git worktree`、`git branch`、`git merge`、`git push`，也不创建 Issue、PR 或改 state；
- 用简短结构化结果报告边界冲突、待澄清项和建议的串行/人工 worktree 下一步。

父会话必须等待全部子智能体并汇总结果，明确说明“通过预检不等于授权并行写入”。
子智能体共享父会话工作目录，不能被描述为隔离 worktree。

若 safety gate 不合格、用户未确认、或原生 `spawn_agent` 工具不可用，停止预检：不模拟
子智能体、不启动独立聊天，报告降级原因并运行既有 `parallel-guidance` 生成用户手动管理的
隔离 worktree 指引。任何 `--refresh` 仍需用户明确确认后才可透传。

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

先读取 `.agent/state.json` 的 `tracker`。`github` 加载 `spec-guard:spec-github-bridge`，
`none` 保持本地流程。GitLab 使用确定性入口，默认只预览：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/sync-map-gitlab.sh"
```

原样转述计划。只有用户明确确认将创建的 Issue 后，才追加 `--confirm` 重跑；脚本会逐条创建
Issue 并写回 state。不要再以 bridge prose 模拟 GitLab 同步。

## `next`

按 `tracker` 路由：`github` 加载 `spec-guard:spec-github-bridge`，`gitlab` 加载
`spec-guard:spec-gitlab-bridge`，`none` 保持本地流程。不要复制或自行改写外部 issue 筛选逻辑。

## `deliver`

按 `tracker` 路由：`github` 加载 `spec-guard:spec-github-bridge`，`gitlab` 加载
`spec-guard:spec-gitlab-bridge`，`none` 保持本地流程。不要在此 skill 中复制 GitHub、GitLab 或交付流程。
