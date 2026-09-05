# 发布证据记录

本目录保存版本化的发布验收记录，不保存推测性结论。每一条记录由
`scripts/release-evidence.py validate` 校验，且只可使用下列状态：

| 状态 | 含义 |
| --- | --- |
| `source-verified` | 当前源码的确定性回归通过 |
| `package-verified` | 指定 artifact 的 manifest 和内容通过机械校验 |
| `installed-verified` | 指定版本在新会话中实际加载 |
| `host-verified` | 指定真实宿主完成目标操作 |
| `project-verified` | 指定 GitHub/GitLab 项目完成旅程 |
| `not-verified` / `unsupported` | 未运行或明确不支持；不推断为通过 |

## 当前支持矩阵

| 接入方式 | 源码证据 | 安装/真实宿主证据 | 写入边界 |
| --- | --- | --- | --- |
| Codex CLI | `source-verified`：adapter、hook 与 smoke 判决器回归 | `not-verified`：需指定新会话与已安装版本 | 显式确认；实验性并行写入口暂停 |
| Codex 桌面 | `source-verified`：共享 skill/hook 回归 | `not-verified`：无原生桌面 UI 观察记录 | 遵从桌面批准；实验性并行写入口暂停 |
| Claude Code CLI | `source-verified`：命令、hook 与 bridge 回归 | `not-verified`：无指定新会话记录 | 显式确认；实验性并行写入口暂停 |
| Claude Code 桌面模式 | `not-verified`：未把它与 MCPB 混同 | `not-verified`：无原生 UI 观察记录 | 不因其他宿主而获得写入结论 |
| Claude Desktop MCPB | `source-verified`：`test-claude-desktop-mcp.sh` | `not-verified`：未记录已安装 MCPB 会话 | 只读；没有写入工具 |

以上行不等同于 GitHub/GitLab 项目验收；项目验收必须另行记录目标仓库、操作范围和
观察结果。完整自动并行执行不在支持范围内。

## 新安装或升级记录模板

在获得用户确认并完成实际操作后，创建 `<version>-<host>.json`。`target.id` 必须包括
版本、会话或项目的稳定身份；不要填写源代码路径代替已安装版本。

```json
{
  "schemaVersion": 1,
  "release": { "version": "0.8.0" },
  "records": [
    {
      "subject": "codex-cli",
      "status": "installed-verified",
      "target": {
        "kind": "installed-session",
        "id": "version:0.8.0;session:<new-session-id>"
      },
      "observedAt": "2026-09-05T14:00:00Z",
      "evidence": ["command:codex plugin list --available --json"]
    },
    {
      "subject": "claude-desktop-mcpb",
      "status": "not-verified",
      "target": { "kind": "host-session", "id": "not-run" },
      "reason": "requires an explicitly approved desktop session"
    }
  ]
}
```

真实项目、发布、打 tag、安装/升级插件、创建 tracker 数据或运行桌面会话均须逐次获得
用户确认。离线、未认证、缺插件或无可用桌面会话时，保留 `not-verified` 和原因；不要
删除失败记录，也不要把命令退出 0 当作任务验收。
