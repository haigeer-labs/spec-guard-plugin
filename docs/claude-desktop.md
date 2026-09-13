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

`setup`、创建/刷新 Issue、MR 创建/合并、history import、lifecycle、`next`、`deliver` 与 teardown
没有 MCP 工具入口。写入请在 Claude Code CLI、Codex CLI 或 Codex 桌面版中明确说明影响范围并确认后执行。

GitHub 预览与 GitLab 确定性入口都先调用同一能力图解析器。Spec Guard 始终严格串行推进；
为兼容上游格式，Build order 的逗号分组会按左到右展开为单模块步骤，依赖仍只取 `Depends on`。
图无效、Python 不可用、子进程非零或返回坏 JSON 时，
预览直接返回错误，绝不会退回旧正则解析或报告成功。该保证来自本地协议回归，不等同于 Desktop
原生 UI E2E。

## 四端功能矩阵

| 宿主 | 接入方式 | 只读检查/预览 | 本地或远端写入 |
| --- | --- | --- | --- |
| Claude Code CLI | Claude plugin slash command | 支持 | 支持；执行前确认 |
| Claude Desktop | 本地 MCPB | 支持 | 不提供；切换至 CLI/Codex |
| Codex CLI | Codex plugin skill/hook | 支持 | 支持；sandbox 可能要求批准 `gh`/`glab` |
| Codex 桌面版 | Codex plugin skill | 支持 | 支持；遵从桌面端批准流程 |

## 验证

```bash
/bin/bash plugins/spec-guard/hooks/test-claude-desktop-mcp.sh
/bin/bash scripts/validate.sh
```

安装后先调用 `phase`，并传入目标项目的绝对 Git 根路径。相对路径、子目录和不存在路径会返回错误，
不会扫描或修改其他位置。
