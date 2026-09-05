# Spec: parallel-execution-ledger

## Objective

提供 Worktree 并行运行的唯一控制账本：一个 run 只能为一个经批准的能力图快照和基线 SHA
服务；同一模块在同一 run 内只能被一个有效 worker 持有。账本放在 Git common directory，
所以同一 clone 的 linked worktree 都可见，但不会进入业务 PR，也不扩展 `.agent/state.json`。

## Tech Stack

- Python 3 标准库：JSON schema 校验、SHA-256、原子目录创建和稳定文本/JSON 输出。
- Git：仅查询 `rev-parse --git-common-dir`、`remote` 与 commit SHA。
- Bash 3.2：命令入口和临时 Git 仓库回归夹具。

## Commands

```bash
python3 plugins/spec-guard/hooks/parallel-execution.py create-run --project . --safety-report <path>
python3 plugins/spec-guard/hooks/parallel-execution.py claim-module --project . --run <run-id> --module <module-id>
python3 plugins/spec-guard/hooks/parallel-execution.py status --project . --run <run-id> --format json
/bin/bash plugins/spec-guard/hooks/test-parallel-execution-ledger.sh
```

## Interface Contract

`runId` 必须由规范化 remote、精确 base SHA、能力图 goal digest 与按 build order 排列的
module row digest 计算；重试同一意图得到同一 runId。账本路径固定为
`<git-common-dir>/spec-guard/parallel/v1/`，未知 schema version 一律拒绝。

`claim-module` 以单次 `mkdir leases/module-<module-id>` 领取模块。已存在时返回结构化
`CONFLICT` 并非零退出，绝不检查后再创建。每份 lease 记录 runId、moduleId、workerId、
owner、base SHA、创建/续期时间和状态。调用结果只有成功、明确失败或 `unknown`；超时不能被
当作失败后安全重试。

worker manifest 必须包含唯一 module、基线、lease 路径、边界摘要和 schema version。它是
worker 模式的唯一任务范围来源；不是 `.agent/state.json.activeModule` 的副本。

## Project Structure

```text
plugins/spec-guard/hooks/parallel-execution.py       → 账本 CLI 与 schema 校验
plugins/spec-guard/hooks/parallel_execution_lib.py   → 内部路径、身份和原子 lease 操作
plugins/spec-guard/hooks/test-parallel-execution-ledger.sh → Git 夹具回归
```

## Testing Strategy

- 相同输入生成相同 runId，不同 base 或能力图 digest 生成不同 runId。
- 两个进程竞争同一 module，恰好一个成功；不同 module 可分别领取。
- 损坏/未知版本 manifest、common-dir 不同、过期/unknown lease 均 fail closed。
- 账本不写工作树、不修改 `.agent/state.json`、能力图或 tracker。

## Boundaries

- Always: 在写 lease 前验证 Git common directory 和安全门报告；所有 JSON 严格校验。
- Ask first: 清除 unknown lease、改变 schema version 或 TTL 策略。
- Never: 以 GitHub/GitLab assignee 充当锁；跨 clone 宣称互斥；改动现有 state schema。

## Success Criteria

1. 同 clone 的重复模块 worker 必定只有一个取得写入资格。
2. 所有账本状态能关联到 run、module、base SHA 与创建者。
3. 任意不完整、过期或无法判定的状态都不能开启 worker。

## Parallel Boundary

```json
{
  "paths": ["plugins/spec-guard/hooks/parallel-execution.py", "plugins/spec-guard/hooks/parallel_execution_lib.py", "plugins/spec-guard/hooks/test-parallel-execution-ledger.sh"],
  "publicInterfaces": ["parallel-execution-cli-v1", "parallel-worker-manifest-v1"],
  "migrations": [],
  "globalConfig": [],
  "testResources": []
}
```
