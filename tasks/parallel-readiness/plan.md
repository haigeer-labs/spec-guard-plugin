# Implementation Plan: parallel-readiness

## Overview

实现一个宿主中立、只读的能力图并行候选分析器。它对已评审能力图计算依赖层，
以可追溯的默认分支 commit SHA 输出候选组，并把“候选”与“安全可并行”严格分离。

> Task tracker: GitHub Issues（尚未同步）。以下为待用户确认 `/sync-map` 后映射的
> 任务卡，不是本地 `todo.md`，也不代表任务已被领取。

## Architecture Decisions

- 将能力图解析集中到 `capability_map.py`；`spec-digest.py` 和新分析器共同使用，
  防止依赖语义出现两个版本。
- 默认以 `origin/HEAD` 的本地跟踪 ref 分析，报告 `fresh=false`；仅 `--refresh`
  执行 fetch 且成功时才报告 `fresh=true`。
- 输出 JSON 是稳定机器接口；文本仅为人类说明。所有成功候选统一标为
  `candidate-only`，安全结论留给下一模块。
- 新功能作为显式 Claude 命令与 Codex skill 操作，不接入 `UserPromptSubmit` hook，
  避免每轮对话触发 Git 或网络检查。

## Dependency Graph

```text
capability_map.py + spec-digest regression
             ↓
parallel-readiness.py candidate analysis
             ↓
fake-remote freshness / no-side-effect regression
             ↓
Claude command + Codex skill + README discoverability
```

## Task List

### Phase 1: Shared parsing foundation

#### Task 1: Extract and validate the shared capability-map parser

**Description:** Move the module-table, dependency and build-order parsing into one
importable Python module, then refactor `spec-digest.py` to use it without changing its
existing `compute`/`check` JSON output.

**Acceptance criteria:**

- Valid maps preserve existing row order and digest behaviour.
- Parser rejects unknown, cyclic, self and malformed dependencies, invalid ids and invalid
  build order with actionable diagnostics.
- `spec-digest.py --selftest` remains green without callers needing a new interface.

**Verification:**

- `python3 plugins/spec-guard/hooks/spec-digest.py --selftest`
- Focused parser cases in `test-parallel-readiness.sh` fail for every invalid graph class.

**Dependencies:** None.

**Files likely touched:**

- `plugins/spec-guard/hooks/capability_map.py`
- `plugins/spec-guard/hooks/spec-digest.py`
- `plugins/spec-guard/hooks/test-parallel-readiness.sh`

**Estimated scope:** M (3 files).

### Phase 2: Candidate analysis

#### Task 2: Implement deterministic baseline and dependency-layer reporting

**Description:** Add `parallel-readiness.py` with text and JSON outputs. Resolve the
remote default branch safely, pin output to its complete SHA, and calculate only
same-layer groups containing at least two modules.

**Acceptance criteria:**

- JSON contains `ok`, `base.ref`, 40-character `base.sha`, `base.fresh`, warnings and
  `candidateGroups` in deterministic order.
- Candidate groups are always `candidate-only`; no text or JSON implies safety approval.
- Invalid maps and unresolved default branch refs fail clearly without writing project files.

**Verification:**

- Focused positive and invalid-map cases in `test-parallel-readiness.sh`.
- Manual text/JSON inspection in a temporary Git fixture with a non-`main` default branch.

**Dependencies:** Task 1.

**Files likely touched:**

- `plugins/spec-guard/hooks/parallel-readiness.py`
- `plugins/spec-guard/hooks/test-parallel-readiness.sh`

**Estimated scope:** S (2 files).

### Checkpoint: Core analysis

- Parser and analyzer focused tests pass.
- A two-root-module fixture yields one `candidate-only` group and an exact base SHA.
- A malformed map yields no candidate group.

### Phase 3: Freshness and regression protection

#### Task 3: Prove refresh and no-side-effect semantics with local Git fixtures

**Description:** Extend the focused harness with a local bare remote so it can prove
that `--refresh` updates the remote-tracking baseline, a failed fetch never claims
freshness, and ordinary analysis leaves HEAD, index, worktree and `.agent/state.json`
unchanged.

**Acceptance criteria:**

- No-refresh runs do not invoke fetch and report `fresh=false`.
- Successful explicit refresh reports the fetched SHA and `fresh=true`.
- Failed refresh exits nonzero and produces no result claimed as latest.

**Verification:**

- `/bin/bash plugins/spec-guard/hooks/test-parallel-readiness.sh`
- `git diff --exit-code` against fixture before/after no-refresh analysis.

**Dependencies:** Task 2.

**Files likely touched:**

- `plugins/spec-guard/hooks/test-parallel-readiness.sh`
- `plugins/spec-guard/hooks/parallel-readiness.py`

**Estimated scope:** S (2 files).

### Phase 4: Explicit host entry points

#### Task 4: Expose the analysis without changing lifecycle orchestration

**Description:** Add an opt-in Claude command and Codex `spec-guard-ops` operation,
then document the command and the candidate-only limitation. Do not attach it to the
phase hook or existing `/next` flow.

**Acceptance criteria:**

- Both hosts invoke the same deterministic script and explain `--refresh` confirmation.
- Documentation never calls candidates “safe parallel work” and never promises automatic
  worktree or agent lifecycle management.
- Repository command-name and README-sync checks remain green.

**Verification:**

- `/bin/bash scripts/test-checkers.sh`
- `/bin/bash scripts/validate.sh`
- Read the generated command/skill instructions to confirm no unapproved automatic action.

**Dependencies:** Task 3.

**Files likely touched:**

- `plugins/spec-guard/commands/parallel-readiness.md`
- `plugins/spec-guard/skills/spec-guard-ops/SKILL.md`
- `README.md`
- `scripts/check-command-names.py` (only if its allowlist requires the new command)

**Estimated scope:** M (3-4 files).

### Checkpoint: Ready for review

- Focused harness, `spec-digest.py --selftest` and `scripts/validate.sh` pass.
- No change to `.agent/state.json`, `/next`, tracker write paths or task/worktree creation.
- Human review confirms the output uses `candidate-only` rather than a safety claim.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| 依赖图解析与既有 digest 语义漂移 | High | 单一解析器、保留 digest 自检、先做回归任务。 |
| 本地 `origin/*` 过期却被当作最新 | High | 默认 `fresh=false`；只让成功的显式刷新升格为 fresh。 |
| 用户把候选组误解为可自动并行 | High | 固定分类为 `candidate-only`，每种输出都带限制说明。 |
| 隐式网络或工作区副作用 | High | `--refresh` 显式开关、本地 remote 回归和 no-side-effect 断言。 |
| 新入口干扰现有单模块流程 | Medium | 仅显式命令/skill，禁止修改 phase hook、`/next` 和 state。 |

## Open Questions

- 在下一模块 `parallel-safety-gate` 中，模块边界声明应放在每份模块 spec 的哪一个
  标准章节；这需要单独设计，不能由本模块猜测。
- 是否将 `--refresh` 作为宿主确认操作：当前规格要求先征询用户；CLI 参数本身仍须
  由宿主在获得确认后传入。
