---
description: 按需查看当前 Initiative 的 agent-skills 工作流路线图
allowed-tools: Bash
---

这是只读查询，不创建或更新 state、task、Issue、PR/MR、binding、worktree、分支或运行进程。
阶段交接、确认或停止前，优先读取本轮 hook 注入的 `checkpoint-rules:` 绝对路径；没有该事实时，读取插件根目录中的共享规则：

```bash
CHECKPOINT_RULES="${CLAUDE_PLUGIN_ROOT}/references/workflow-checkpoints.md"
[ -f "$CHECKPOINT_RULES" ] && sed -n '1,260p' "$CHECKPOINT_RULES"
```

从当前插件根与项目根运行共享路线图脚本：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
python3 -B "${CLAUDE_PLUGIN_ROOT}/hooks/workflow_roadmap.py" --project "$PROJECT"
```

若 `.agent/state.json` 声明 `tracker=github` 且不在 `local-validation` 阶段，先运行：

```bash
gh auth status --hostname github.com
```

认证或凭据状态不可用时仍可运行路线图以展示本地事实，但必须明确说明远端状态会保持未知；不要把它说成 Issue 不存在。
若错误明确为 GitHub API 网络不可用，说明当前 shell 的网络或沙箱权限阻止查询，不要归因于 Keychain。
仅当错误明确指向凭据访问（例如 Keychain 不可见或 token 无效）时，才请求用户授权以允许该 shell 访问凭据后重试；绝不要求用户粘贴 token，也不自动登录。

用户明确要求查看活跃能力图的全部模块时，才追加 `--all`。默认只显示当前模块及其直接依赖和后继，
避免把整图带入每次交互。

如脚本报告 Initiative、能力图或当前模块无法唯一确认，原样说明不确定性；不要通过文件新旧、分支名、
模块数量或 Issue 编号猜测。`linked worktree`、分支和 detached HEAD 仅说明代码执行位置，不是模块
绑定、任务领取或并行写入授权。`local-validation` 下不得建议 tracker 同步、领取、绑定或交付。
