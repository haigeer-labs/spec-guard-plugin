# Implementation Plan: parallel-execution-ledger

## Overview

为后续 Worktree runtime 和 CLI worker 提供一个同 clone 可见、版本化且 fail-closed 的控制账本。
本模块只建立 run、lease、manifest 与状态查询；不创建 Worktree、不启动 agent、不写 tracker，亦不
改变 `.agent/state.json` 的单 `activeModule` 契约。

> Tasks tracked in GitHub Issues #95。下列为已评审前的有序草案；确认后才创建 task 子 Issue 并
> 将此处替换为 Issue 编号索引。

## Architecture Decisions

- 账本根目录由 `git rev-parse --git-common-dir` 推导为
  `<common-dir>/spec-guard/parallel/v1`，而非工作树或仓库内容；不同 worktree 共享、PR 不携带。
- `runId` 是已批准输入的确定性 SHA-256 身份，不是每次运行生成的随机值；同一意图的重试只复用
  同一 run，不覆盖不同基线的 run。
- 模块 lease 用原子 `mkdir` 领取；第二个请求返回明确 conflict。超时/中断造成的结果是 `unknown`，
  而不是可安全重试的失败。
- 所有外部 JSON（safety report、已有 ledger）在入口校验；未知 schema 和不完整记录均 fail closed。

## Dependency Graph

```text
validated safety report + capability-map digest + Git common-dir
                         │
                         ▼
                 T1 identity/storage primitives
                         │
                         ▼
                    T2 create-run CLI
                         │
                         ▼
              T3 atomic module lease + manifest
                         │
                         ▼
              T4 status / unknown-state contract
```

## Task List

### Phase 1: Stable identity and storage

- #100 建立 parallel execution ledger 的身份与存储基元。Depends on: none. Scope: M (3 files).

### Phase 2: Run creation and exclusive ownership

- #101 实现经安全门验证的并行 run 创建（blocked by #100）。Scope: M (3 files).
- #102 实现模块原子 lease 与 worker manifest（blocked by #100、#101）。Scope: M (3 files).

### Checkpoint: ledger correctness

- #103 Checkpoint: 验证 ledger 的并发互斥与基础回归（blocked by #102）。

### Phase 3: Observable recovery state

- #104 实现 ledger 状态查询与 unknown 恢复契约（blocked by #103）。Scope: S (2 files).

### Checkpoint: module complete

- #105 Checkpoint: 完成 ledger 回归与负向验证（blocked by #104）。

## Task Details

### T1: Identity, schema and storage primitives

**Acceptance criteria**

- `parallel_execution_lib.py` derives the common-dir ledger location and rejects non-Git, missing or escaping
  paths.
- The run identity is stable for identical normalized inputs and changes when remote, base SHA, goal digest or
  ordered module digest changes.
- Versioned JSON records reject unknown version, missing required fields and invalid module IDs.

**Verification**

- Focused test proves deterministic identity and positive/negative schema cases.
- Focused test proves no write occurs in the checked-out repository or `.agent/state.json`.

**Files likely touched**

- `plugins/spec-guard/hooks/parallel_execution_lib.py`
- `plugins/spec-guard/hooks/test-parallel-execution-ledger.sh`
- `plugins/spec-guard/hooks/parallel-execution.py`

### T2: Create a validated run

**Acceptance criteria**

- `create-run` accepts only an eligible safety report whose base and ordered modules match the current
  capability map.
- Retrying the same intent returns the existing compatible run; mismatched existing records fail visibly.
- A created record stores enough provenance to make later worker validation independent of mutable text output.

**Verification**

- Tests cover compatible retry, stale base, bad report and pre-existing mismatched run.
- Command emits stable JSON for automation and concise text for users.

**Files likely touched**

- `plugins/spec-guard/hooks/parallel-execution.py`
- `plugins/spec-guard/hooks/parallel_execution_lib.py`
- `plugins/spec-guard/hooks/test-parallel-execution-ledger.sh`

### T3: Exclusive module lease and manifest

**Acceptance criteria**

- Competing claims for one module yield exactly one winner by atomic directory creation.
- Different modules can be claimed independently under one valid run.
- The issued manifest carries run, worker, module, base and schema identity, while canonical state remains
  unchanged.

**Verification**

- A concurrent test fixture asserts one success and one structured conflict for a shared module.
- Negative tests cover invalid module, expired/unknown lease and common-dir mismatch.

**Files likely touched**

- `plugins/spec-guard/hooks/parallel_execution_lib.py`
- `plugins/spec-guard/hooks/parallel-execution.py`
- `plugins/spec-guard/hooks/test-parallel-execution-ledger.sh`

### T4: Status and unknown-state recovery contract

**Acceptance criteria**

- `status` reports every run/module state using stable JSON and a human-readable equivalent.
- Malformed, expired or interrupted records become observable `unknown`/blocked states, never silently reusable
  leases.
- Status reads do not mutate records, Git state or tracker state.

**Verification**

- Tests cover healthy, conflict, malformed, expired and unknown records.
- `scripts/validate.sh` remains green after adding the new hook/test files.

**Files likely touched**

- `plugins/spec-guard/hooks/parallel-execution.py`
- `plugins/spec-guard/hooks/test-parallel-execution-ledger.sh`

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Safety report JSON contract differs from its documented shape | Wrong run may be admitted | Read existing report emitter before T2; fixture its actual JSON and reject unknown/missing fields. |
| Filesystem operation is not atomic on an unsupported volume | Duplicate module writers | P0 supports only the local common-dir claim; test it and fail closed when identity cannot be proven. |
| A process dies after lease creation | Unsafe duplicate retry | Record `unknown`, require explicit recovery/discard in a later module; never infer failure. |
| New hook guard creates false diagnostics | Users lose trust in workflow | Positive and negative fixture cases; test ordinary non-parallel projects unchanged. |

## Open Questions

- What TTL and explicit recovery UX should a later workflow module expose? This ledger module records the state
  but does not automatically reclaim it.
- Whether a manifest needs a cryptographic MAC is deferred: P0 trusts local filesystem ownership and rejects
  cross-clone coordination rather than claiming distributed security.
