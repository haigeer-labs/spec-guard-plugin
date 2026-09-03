# Implementation Plan: parallel-safety-gate

## Overview

在 `parallel-readiness` 的同层候选基础上，读取每个模块 spec 中显式、机器可读的
边界声明，保守判定是否只“可人工启动隔离并行”。缺失、无效或任一冲突均不可推荐并行。

> Task tracker: GitHub Issues（尚未同步）。以下是待用户确认 `/sync-map` 后映射的
> 任务卡，不创建本地 `todo.md`，也不代表任务已领取。

## Architecture Decisions

- 用 `## Parallel Boundary` 下唯一 JSON fenced block 作为唯一声明输入；不从自然语言、
  分支名或历史提交推断所有权。
- 复用 `parallel-readiness.py` 的 `report(..., refresh=...)`，不复制默认分支、fetch 或
  SHA 逻辑。
- 路径按仓库根相对路径比较；任何父目录/子路径重叠即冲突。资源类非空默认串行。
- 输出分类仅为 `manual-parallel-eligible`、`needs-review` 或 `sequential-required`；不使用
  “safe/approved/automatic”。

## Dependency Graph

```text
JSON boundary parser + invalid-declaration regression
                    ↓
candidate pair conflict classifier
                    ↓
readiness baseline / refresh integration
                    ↓
explicit Claude + Codex entry points and documentation
```

## Task List

### Phase 1: Boundary declaration foundation

#### Task 1: Parse and validate module boundary declarations

**Description:** Add a focused parser for the unique `## Parallel Boundary` JSON block
in module specs. Validate all required arrays and reject missing headings, duplicate blocks,
invalid JSON, path escapes, absolute paths and globs.

**Acceptance criteria:**

- All five required fields are arrays and their string values are normalized deterministically.
- Exactly one boundary declaration is accepted per module spec.
- Invalid declarations produce diagnostics and never silently become empty boundaries.

**Verification:**

- `/bin/bash plugins/spec-guard/hooks/test-parallel-safety-gate.sh`
- Focused fixtures cover every invalid declaration class.

**Dependencies:** None.

**Files likely touched:**

- `plugins/spec-guard/hooks/parallel-safety-gate.py`
- `plugins/spec-guard/hooks/test-parallel-safety-gate.sh`

**Estimated scope:** S (2 files).

### Phase 2: Conservative conflict classification

#### Task 2: Classify candidate pairs using declared ownership

**Description:** Compare every pair in a readiness candidate group. Detect equal and
ancestor/descendant path overlap, shared public interfaces, nonempty serial resources and
shared test resources; produce stable evidence and the strictest group classification.

**Acceptance criteria:**

- A fully declared, disjoint, resource-empty pair is `manual-parallel-eligible` only.
- Missing or invalid declarations yield `needs-review`.
- Any concrete overlap or nonempty serial resource yields `sequential-required` with module
  pair and category evidence.

**Verification:**

- Pairwise path/API/resource fixtures in the focused harness.
- JSON output order is deterministic across repeated runs.

**Dependencies:** Task 1.

**Files likely touched:**

- `plugins/spec-guard/hooks/parallel-safety-gate.py`
- `plugins/spec-guard/hooks/test-parallel-safety-gate.sh`

**Estimated scope:** S (2 files).

### Checkpoint: Safety classification

- All missing and conflict scenarios refuse a parallel recommendation.
- The sole positive fixture contains disjoint explicit declarations and emits only
  `manual-parallel-eligible`.
- No script changes state, branches, worktrees or tracker records.

### Phase 3: Baseline integration

#### Task 3: Reuse readiness baseline and refresh semantics

**Description:** Wire the safety gate to the existing readiness report so base ref, full SHA,
candidate grouping, success/failure and explicit refresh behavior are identical.

**Acceptance criteria:**

- Gate output copies the readiness `base` object without reimplementing Git commands.
- `--refresh` succeeds/fails with the same truthfulness guarantees as readiness.
- No-refresh gate runs leave HEAD and project files unchanged.

**Verification:**

- Local bare-remote fixture tests for stale, refreshed and failed remote scenarios.
- Existing `test-parallel-readiness.sh` remains green.

**Dependencies:** Task 2.

**Files likely touched:**

- `plugins/spec-guard/hooks/parallel-safety-gate.py`
- `plugins/spec-guard/hooks/test-parallel-safety-gate.sh`

**Estimated scope:** S (2 files).

### Phase 4: Explicit host integration

#### Task 4: Add opt-in host instructions and guard regression

**Description:** Expose the gate through an explicit Claude command and Codex operation;
document that refresh needs confirmation and eligibility is not automatic execution. Extend
the Codex adapter regression accordingly.

**Acceptance criteria:**

- Both hosts invoke the same script and never attach it to `UserPromptSubmit`.
- Documentation says missing/conflicting declarations require sequential work or review.
- Command checks, adapter checks and README checks remain green.

**Verification:**

- `/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh`
- `python3 scripts/check-command-names.py`
- `/bin/bash scripts/validate.sh`

**Dependencies:** Task 3.

**Files likely touched:**

- `plugins/spec-guard/commands/parallel-safety-gate.md`
- `plugins/spec-guard/skills/spec-guard-ops/SKILL.md`
- `plugins/spec-guard/hooks/test-codex-adapter.sh`
- `README.md`

**Estimated scope:** M (3-4 files).

### Checkpoint: Ready for review

- Focused safety and existing readiness harnesses pass.
- Full validation passes.
- No output uses safe/approved/automatic language or performs lifecycle work.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| 边界声明被自然语言替代、解析后静默为空 | High | 只接受唯一 JSON block；任何错误均为 `needs-review`。 |
| 目录拥有权漏掉子文件冲突 | High | 双向祖先/后代路径交集，专门回归。 |
| 复制 Git freshness 逻辑后产生漂移 | High | 直接复用 readiness report，不新写 Git 基线函数。 |
| eligibility 被误读为自动调度许可 | High | 固定分类命名、双宿主说明与回归禁止 hook 接入。 |
| 公共资源命名不统一 | Medium | 同名即冲突；不同名称不推断相等，交给人工复核。 |

## Open Questions

- 若未来需要对非空迁移/测试资源申请人工豁免，应单独设计可审计的显式豁免格式；本模块
  不提供该能力。
