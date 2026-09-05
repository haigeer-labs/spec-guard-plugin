# Implementation Plan: parallel-cli-execution

## Overview

在已验证的 controller-owned worktree 中以受控 argv 启动 Codex CLI 或 Claude CLI，并把进程状态
保存在 ledger；不允许 worker 自选 cwd、嵌套创建 worktree 或把 unknown 重试为新 worker。

> Tasks tracked in GitHub Issues #97。

## Architecture Decisions

- adapter 只接收已验证 worker manifest，不接受自由 module、路径或 shell 字符串。
- 使用 argv 形式的 `subprocess`，Codex 固定为 `codex -C <path>`；Claude 不加 `--worktree`。
- started、completed、failed、unknown 是显式状态；unknown 永不自动重试。

## Dependency Graph

```text
verified runtime worker → T1 adapter contract → T2 start/ledger state
                                               → T3 inspect/unknown → T4 checkpoint
```

## Task List

### Phase 1

- #114 建立 Codex/Claude adapter 的受控 argv 与 binary 检测。
- #115 实现启动、退出状态与 ledger 运行记录。

### Checkpoint

- #116 Checkpoint: 验证 adapter cwd、参数和非零退出安全性。

### Phase 2

- #117 实现 inspect 与 unknown 状态的只读可观测性。

### Final checkpoint

- #118 Checkpoint: 完成 fake binary、超时/中断与 mutation 负向验证。

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| CLI 在 controller checkout 执行 | manifest + runtime verify 后才派生 cwd；fake binary 断言 cwd。 |
| 参数注入或嵌套 worktree | argv 调用；adapter 禁止自由 shell 和 Claude `--worktree`。 |
| 超时被误判失败并重启 | 固化为 `unknown`，保留 lease 等待人工处理。 |
