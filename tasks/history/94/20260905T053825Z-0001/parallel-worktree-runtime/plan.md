# Implementation Plan: parallel-worktree-runtime

## Overview

将经 `parallel-execution-ledger` 领取的模块安全映射为 controller-owned Git linked worktree。
本模块只管理本插件创建且在 ledger 中登记的资源；不启动 agent、不修改 tracker，也不把任意
本地目录当作可回收资源。

> Tasks tracked in GitHub Issues #96。

## Architecture Decisions

- worker 身份只从 ledger manifest 读取；运行时要再次验证 common-dir、run、module 与基线 SHA，
  不能信任调用方提供的路径。
- provision 以 `git worktree add` 的真实元数据作为成功条件；worktree 路径固定在 common-dir 下的
  controller-owned 命名空间，重复名称拒绝而不覆盖。
- verify 只读检查 worktree、分支、HEAD、clean 状态和基线；任何不可判定结果均拒绝启动 worker。
- reclaim 不递归删除目录，只调用 Git 的 worktree remove，并且要求 owner=`spec-guard` 与显式
  `--confirm` discard 或已合并证明。

## Dependency Graph

```text
ledger manifest + Git common-dir
              │
              ▼
       T1 runtime identity validation
              │
              ▼
       T2 provision linked worktree
              │
              ▼
       T3 read-only worker verification
              │
              ▼
       T4 owned-only reclaim
              │
              ▼
       T5 final negative/mutation checkpoint
```

## Task List

### Phase 1: Safe resource foundation

- #107 建立 runtime 的 manifest、路径和 Git 元数据校验基元。
- #108 实现 controller-owned linked worktree provision（blocked by #107）。

### Checkpoint: provision safety

- #109 Checkpoint: 验证真实 Git fixture 中的基线、重复名称与失败回滚（blocked by #108）。

### Phase 2: Verification and lifecycle

- #110 实现只读 worktree verify 与 fail-closed 结果（blocked by #109）。
- #111 实现 owner-only、confirm/merged 条件下的 reclaim（blocked by #110）。

### Checkpoint: module complete

- #112 Checkpoint: 完成完整回归与 destructive-path 负向验证（blocked by #111）。

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| 路径或 common-dir 被伪造 | 删除或运行到错误 checkout | 从 Git 与 ledger 双重验证，绝不接受自由路径。 |
| provision 中断留下半成品 | 后续 worker 误用资源 | 只在 Git 元数据和 ledger 登记同时完整时返回成功；其余 fail closed。 |
| reclaim 删除用户 worktree | 数据丢失 | owner、worker identity、显式 confirm/merged 三道条件，且不用递归删除。 |
| 非标准 Git 仓库行为 | 误判隔离 | 使用临时真实仓库覆盖 bare、linked、脏树与 submodule 夹具。 |

## Open Questions

- setup 与基线测试的具体命令由后续 workflow 配置提供；本模块只保留其失败即阻断的接口，
  不自行猜测项目命令。
