# Implementation Plan: Claude Desktop MCP Adapter

## Overview

为 Claude Desktop 提供一个无第三方依赖的本地 stdio MCP server。它只封装现有的确定性
spec-guard 检查和预览入口，不复制 tracker 规则，也不暴露写工具。

> Tasks tracked in GitHub Issues: #72, #73, #74.

## Architecture Decisions

- Claude Desktop 自带的 Node.js 标准库处理 newline-delimited JSON-RPC 2.0，避免为小型本地
  server 引入 npm/PyPI 运行时与安装风险，并可打包为 MCPB。
- server 从自身文件位置解析插件根；项目路径只接受调用参数中的绝对 Git 根，hook 仍是唯一
  业务规则来源。
- MCP tool call 不等于远端授权：写意图使用 `write_operation` 返回确认边界；首期不注册任何
  写工具。
- GitLab preview 调用既有确定性脚本；GitHub preview 只解析能力图/state 并列出投影，local
  模式明确不支持远端同步。

## Task List

### Phase 1: Protocol and read-only tools

1. [#72](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/72) — 实现 stdio
   JSON-RPC 生命周期、固定工具目录及 `phase`、`verify`、`verify_history`、`write_operation`。
   - Verify: 协议 fixture 和三种 tracker 的只读调用。

### Phase 2: Tracker preview

2. [#73](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/73) — 实现
   `sync_map_preview` 的 GitHub/GitLab/local 路由。
   - Verify: 三类临时项目零写入，GitLab 复用现有 preview。

### Phase 3: Distribution evidence

3. [#74](https://github.com/yizhongkaimail-collab/spec-guard-plugin/issues/74) — 增加协议回归、
   Claude Desktop MCPB manifest、安装文档与四端矩阵。
   - Verify: focused test、`scripts/validate.sh` 与 MCP Inspector/Claude Desktop 手动发现。

### Checkpoint: Complete

- [ ] 所有三项 Issue 已关闭且模块 #71 可交付。
- [ ] 新 MCP 工具全部零写入；现有 Claude/Codex plugin 回归通过。
- [ ] Claude Desktop 可发现工具，且写操作没有 MCP 入口。

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Claude Desktop 的协议版本差异 | 无法完成 initialize | 仅实现基础 lifecycle/tools，测试协商与错误响应。 |
| stdout 被 hook/日志污染 | MCP connection 失败 | server 捕获 hook stdout 为 tool result，server diagnostics 仅写 stderr。 |
| Desktop tool call 被误解为写授权 | 高 | 不注册写工具，`write_operation` 永远不执行命令。 |
| GitHub preview 与现有同步漂移 | 中 | 仅读取 capability map/state，复用 digest 与解析约束；回归覆盖。 |

## Open Questions

- Claude Desktop 的本机 UI 是否会对每次本地 MCP 调用显示确认；该实现不依赖其存在。
