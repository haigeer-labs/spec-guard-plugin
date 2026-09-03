# Spec: claude-desktop-mcp

## Objective

让 Claude Desktop 通过一个本地 stdio MCP Server 使用 spec-guard 的确定性操作，而不依赖
Claude Code 的 slash-command 插件机制。服务器以明确工具和 JSON Schema 暴露只读状态检查及
同步预览；任何会修改项目、GitHub/GitLab 或历史账本的操作都必须返回“需要确认”的说明，不能
直接执行。

成功时，用户可把服务器加入 Claude Desktop 的 `claude_desktop_config.json`，选择项目根后调用
与 CLI/Codex 同一套 phase、verify、history verify 和 GitHub/GitLab sync-map preview。

## Tech Stack

- Python 3 标准库：newline-delimited JSON-RPC 2.0 stdio server、输入校验与子进程调用；不新增
  PyPI/npm 依赖。
- 既有 Bash/Python hooks：`phase-guard.sh`、`verify-artifacts.sh`、`verify-history.sh` 与
  `sync-map-gitlab.sh`，保持它们是业务规则的唯一来源。
- MCP stdio transport：每行一条 UTF-8 JSON-RPC 消息；stdout 只写协议响应，诊断仅写 stderr。

## Commands

```bash
/bin/bash plugins/spec-guard/hooks/test-claude-desktop-mcp.sh
/bin/bash scripts/validate.sh
python3 plugins/spec-guard/mcp/claude_desktop_server.py
```

## Project Structure

```text
plugins/spec-guard/mcp/claude_desktop_server.py    # stdio MCP server
plugins/spec-guard/mcp/claude_desktop_config.json  # 用户复制用的配置模板
plugins/spec-guard/hooks/test-claude-desktop-mcp.sh # JSON-RPC 协议与工具回归
docs/claude-desktop.md                              # 安装、权限和工具矩阵
```

## Tool Contract

所有工具都要求 `project` 是绝对路径、现存目录且 Git 项目根；服务器不得因调用方给出的路径
读取或写入项目外文件。

| Tool | 输入 | 行为 | 副作用 |
| --- | --- | --- | --- |
| `phase` | `project` | 调用 `phase-guard.sh` 并返回其 JSON/文本事实 | 无 |
| `verify` | `project` | 调用 `verify-artifacts.sh`，保留退出码与诊断 | 无 |
| `verify_history` | `project` | 调用 `verify-history.sh` | 无 |
| `sync_map_preview` | `project` | 读取 tracker；GitLab 调用确定性 preview，GitHub 只返回待创建投影清单，本地模式说明没有远端同步 | 无 |
| `write_operation` | `project`, `operation` | 不执行命令；返回将影响的文件/远端对象与“需要用户在 CLI/Codex 中明确确认”的说明 | 无 |

首期没有 `setup`、`sync_map_confirm`、`history_migration_import`、`teardown`、`lifecycle`、`next`
或 `deliver` MCP 写工具。这样不会把 Claude Desktop 的一次工具调用误解释成远端写入授权。

## Code Style

```python
def text_result(text: str, *, is_error: bool = False) -> dict:
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)
```

- 仅 snake_case Python 标识符；工具名使用 MCP kebab-free snake_case。
- 每个 JSON-RPC request 只产生一个同 id 的 result 或 error；notification 不响应。
- 不使用 shell 字符串拼接。调用 hook 时传递 argv 数组和受控环境变量。
- stdout 只能写 JSON-RPC 响应；不得泄露 token、环境变量或完整认证状态。

## Testing Strategy

- 单元/协议：向服务器 stdin 喂入 `initialize`、`tools/list`、未知方法、无效 JSON 与
  `tools/call`，断言 JSON-RPC 格式、确定性工具顺序和 stderr/stdout 隔离。
- 集成：对临时 GitHub、GitLab 与本地项目调用四个只读/预览工具，断言 tracker 正确路由且
  工作树及远端 Issue 列表无变化。
- 回归：模拟不存在路径、非 Git 目录、缺少 glab/gh、损坏 state 与 hook 非零退出；均返回可读
  `isError` 结果而不崩溃。
- 手动：用 Claude Desktop 配置模板启动 server，列出工具并执行一次 `phase`；写工具不可出现。

## Boundaries

- Always: 复用既有 hooks；验证 project 路径；stdout 只输出协议；所有命令使用 argv；回传
  hook 的退出码和可审阅摘要。
- Ask first: 新增依赖、扩展为 HTTP transport、增加任何写工具、修改 GitHub/GitLab Issue、
  改变已有 CLI/Codex 插件行为。
- Never: 在 MCP server 内静默运行写操作；存储或输出认证信息；将 Claude Desktop tool call
  当作 GitHub/GitLab/MR 合并授权；复制 tracker 业务规则。

## Success Criteria

1. Claude Desktop 可按文档启动服务器并发现固定顺序的五个工具。
2. `phase`、`verify`、`verify_history` 与现有 CLI hook 在同一项目返回等价事实。
3. `sync_map_preview` 对 GitHub、GitLab、本地 tracker 选择正确分支，且零写入。
4. 任意写意图只返回确认说明，不执行本地或远端变更。
5. 协议与集成回归测试通过，且现有插件验证不回归。

## Open Questions

- Claude Desktop 的 UI 是否会为本地 MCP tool call 提供单独的逐次确认；首期不依赖该行为，
  因而不暴露写工具。
