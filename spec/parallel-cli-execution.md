# Spec: parallel-cli-execution

## Objective

在 runtime 已验证的 worktree 中启动 Codex CLI 或 Claude Code CLI worker，并将宿主进程的
启动、退出和不可判定状态记录到 ledger。此模块不让 agent 自己选择目录或模块。

## Tech Stack

- Python 3 标准库：adapter 选择、受控子进程、状态序列化。
- 已安装的 `codex`、`claude` 可执行文件；缺失时明确降级，不模拟成功。
- Git：读取 worker cwd 的当前状态。

## Commands

```bash
python3 plugins/spec-guard/hooks/parallel-cli.py start --project . --worker <worker-id> --host codex-cli
python3 plugins/spec-guard/hooks/parallel-cli.py start --project . --worker <worker-id> --host claude-cli
python3 plugins/spec-guard/hooks/parallel-cli.py inspect --project . --worker <worker-id> --format json
/bin/bash plugins/spec-guard/hooks/test-parallel-cli-execution.sh
```

## Interface Contract

Codex adapter 只在 provisioned path 使用 `codex -C <worktreePath>`；Claude adapter 同样在
该 path 启动，不能在已经隔离的 worker 内再次使用 `claude --worktree`。命令参数来自已校验
manifest，不能把 module 名、路径或 prompt 直接拼接为 shell。

启动前必须复验 lease、cwd、common-dir、HEAD 和 branch。启动成功只表示 `started`，不表示
实现成功；退出状态必须是 `completed`、`failed` 或 `unknown`。`unknown` 保留 lease 并等待
人工恢复/处置，不能自动另起同一模块 worker。

## Project Structure

```text
plugins/spec-guard/hooks/parallel-cli.py
plugins/spec-guard/hooks/parallel_cli_adapters.py
plugins/spec-guard/hooks/test-parallel-cli-execution.sh
```

## Testing Strategy

- fake Codex/Claude 二进制验证实际 cwd、参数和 adapter 选择。
- 缺二进制、非零退出、中断、超时、lease 失效均不变成 completed。
- Claude adapter 不传嵌套 `--worktree`；Codex adapter 不假设该 flag 存在。
- 完成记录不写 canonical state 或 tracker。

## Boundaries

- Always: 从 manifest 获取唯一 module 和目录；每次启动前复验 Git 身份。
- Ask first: 传递会访问网络或启动交互式会话的宿主参数。
- Never: 在 controller checkout 写代码、吞掉 host 的失败、自动重试 unknown worker。

## Success Criteria

1. 两种 CLI 都只能在已验证 worker worktree 中运行。
2. worker 运行结果可追溯且任何不确定结果阻断重复写入。
3. 不支持的 host 走明确的手工降级，而不是共享目录执行。

## Parallel Boundary

```json
{
  "paths": ["plugins/spec-guard/hooks/parallel-cli.py", "plugins/spec-guard/hooks/parallel_cli_adapters.py", "plugins/spec-guard/hooks/test-parallel-cli-execution.sh"],
  "publicInterfaces": ["parallel-cli-adapter-v1"],
  "migrations": [],
  "globalConfig": [],
  "testResources": []
}
```
