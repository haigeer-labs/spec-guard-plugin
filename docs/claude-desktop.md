# Claude Desktop MCP Bundle

Claude Desktop 不执行 Claude Code plugin 的 `/spec-guard:*` slash commands。Spec Guard 为它提供
一个本地 Node.js stdio MCP server，并以 MCP Bundle（`.mcpb`）形式安装。这个入口刻意只暴露
只读检查与预览，不将一次桌面 tool call 当作 GitHub/GitLab 写入授权。

## 打包与安装

Claude Desktop 的本地扩展交付方式是 MCPB：一个包含 `manifest.json` 和本地 MCP server 的 zip
archive。安装时 Claude Desktop 启动 server 子进程并通过 stdio 通信；Node.js 是官方推荐的运行时，
Claude Desktop 在 macOS 与 Windows 中自带它。

```bash
npm install -g @anthropic-ai/mcpb
cd plugins/spec-guard
mcpb pack
```

生成的 `.mcpb` 可双击打开，或在 Claude Desktop 中依次选择 **Settings → Extensions → Advanced
settings → Install Extension…** 后选取。安装页面会展示工具与权限；若企业策略禁用本地扩展，需由
管理员启用相应 policy。

官方资料：[构建 MCPB](https://claude.com/docs/connectors/building/mcpb)、
[Claude Desktop 本地 MCP](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop)、
[MCP stdio transport](https://modelcontextprotocol.io/specification/draft/basic/transports)。

## 工具与权限

| 工具 | 行为 | 写入项目或远端？ |
| --- | --- | --- |
| `phase` | 返回现有 `phase-guard.sh` 的阶段事实 | 否 |
| `verify` | 调用 `verify-artifacts.sh` 校验产物 | 否 |
| `verify_history` | 校验 capability history evidence | 否 |
| `sync_map_preview` | GitHub 本地投影预览、GitLab 确定性预览或 local 说明 | 否 |
| `write_operation` | 返回需要确认的下一步 | 否，永不执行 |

`setup`、创建/刷新 Issue、MR 创建/合并、history import、lifecycle、`next`、`deliver`、Desktop worker
登记与 teardown 没有 MCP 工具入口。请在 Claude Code CLI、Codex CLI 或 Codex 桌面版中明确说明影响范围
并确认后执行。

## 四端功能矩阵

| 宿主 | 接入方式 | 只读检查/预览 | 本地或远端写入 |
| --- | --- | --- | --- |
| Claude Code CLI | Claude plugin slash command | 支持 | 支持；执行前确认 |
| Claude Desktop | 本地 MCPB | 支持 | 不提供；切换至 CLI/Codex |
| Codex CLI | Codex plugin skill/hook | 支持 | 支持；sandbox 可能要求批准 `gh`/`glab` |
| Codex 桌面版 | Codex plugin skill | 支持 | 支持；遵从桌面端批准流程 |

## Desktop 原生 worktree worker 登记

Spec Guard 只支持 **register-only**：用户先在 Codex Desktop 或 Claude Code Desktop 创建并选择一个原生
linked worktree，然后才可以将该既有 worker 登记进一个已存在的并行 run。插件不会创建、隐藏、归档或删除
Desktop task/session/worktree，也不会用会话标题、pending client ID 或目录名猜测 worker 身份。

| 宿主 | 登记前必须由操作方取得 | 登记后的资源归属 |
| --- | --- | --- |
| Codex Desktop | 原生 task 的稳定 host worker ID，以及该 task 实际打开的 linked-worktree Git 根目录 | `owner=host`；由 Codex/Desktop 用户回收 |
| Claude Code Desktop | 原生 task 的稳定 host worker ID，以及该 task 实际打开的 linked-worktree Git 根目录 | `owner=host`；由 Claude/Desktop 用户回收 |

登记前，操作方需要从目标 worktree 读取并核对其 Git 根目录、common-dir、非 detached branch 和 HEAD；
它还必须与 run 的 base SHA、目标 module 和尚未占用的 lease 同时匹配。主 checkout、submodule、detached
worktree、没有稳定 host worker ID 或任一核对失败时，登记会失败，不会退回到 controller worktree 或创建新的
Desktop 任务。

在 Claude Code 中，先展示并由用户确认同一个 run、module、host、stable ID 与 cwd，再使用：

```text
/spec-guard:parallel-register-worker <run-id> <module-id> \
  --host <codex-desktop|claude-desktop> --host-worker-id <stable-id> --cwd <absolute-linked-worktree-root>
```

Codex 使用 `spec-guard-ops` 中同名的受控操作。登记成功的 worker manifest 记为 `owner=host`；
`parallel-status` 只显示“宿主可回收”，`parallel-reclaim` 必须停止，绝不能调用 controller reclaim、
`git worktree remove` 或 Desktop archive。

### 原生 E2E 记录（2026-09-05）

本机自动化 Git fixture 已验证登记器会写入 controller ledger、不会写入 Desktop worktree，并拒绝重复 lease、
缺少稳定 ID、主 checkout、错误 module 与 detached HEAD。真实 Desktop UI 验证没有伪造成功：当前 Codex
Desktop 项目 surface 受自动化访问策略限制，无法从插件可调用的公开接口取得目标 native worker 的 cwd 与稳定 ID；
当前 Claude Desktop 会话也没有暴露可登记的目标项目 worktree/cwd 与稳定身份。因此两端在这台测试机上均按
fail-closed 处理，未登记任何 host worker。待宿主 UI 能明确提供这两项值时，按上面的核对和确认流程重跑即可。

## 验证

```bash
/bin/bash plugins/spec-guard/hooks/test-claude-desktop-mcp.sh
/bin/bash plugins/spec-guard/hooks/test-desktop-worker-registration.sh
/bin/bash scripts/validate.sh
```

安装后先调用 `phase`，并传入目标项目的绝对 Git 根路径。相对路径、子目录和不存在路径会返回错误，
不会扫描或修改其他位置。
