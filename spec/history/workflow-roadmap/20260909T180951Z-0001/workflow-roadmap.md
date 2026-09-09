# Spec: workflow-roadmap

## Objective

为使用 `agent-skills` 的用户提供一个按需调用、只读的工作流路线图，解决“只能知道下一步，
不知道正常全链路、当前位置、下一检查点和何时算完成”的问题。

该能力服务于当前活跃 Initiative；没有能力图时退化为单模块路线图。它必须把上游
`agent-skills` 的阶段与 Spec Guard 的运行模式、tracker 事实和 Git 执行上下文分开呈现，
而不是创建第二套状态机或进度真相源。

## User-facing Contract

### Entry points

- `/spec-guard:roadmap`：展示当前 Initiative、当前模块和直接依赖/后继的路线图。
- `/spec-guard:roadmap --all`：仅展开当前活跃能力图中的全部模块矩阵；不混入历史 Initiative。
- Codex 通过 `spec-guard-ops` 的同名只读操作获得等价语义。宿主入口可以不同，但输出边界相同。
- 既有 `/phase` 继续是自动、紧凑的阶段摘要；只补充分支/HEAD、worktree 类型和 dirty 概况，
  不在每轮注入完整路线图，也不联网。

### Required output

路线图按固定顺序呈现：

1. 上游正常路径：可选 Phase 0 Capability Map → Specify → Plan → Tasks → Implement →
   Test/Review/Ship；tracker 的 Issue/PR/MR 交付作为 Spec Guard 扩展层单列。
2. 活跃 Initiative 身份、能力图路径和唯一性结果。
3. 当前模块、显式依赖和后继；只有能力图明确表达依赖时才画箭头，不能把表格顺序当依赖。
4. 上游流程位置、Spec Guard 内部探测状态、当前工作模式和任务事实，分别标注来源。
5. 当前可执行动作与执行权限；“建议下一步”不得被写成“已获授权”。
6. 最近的已声明检查点、条件、到达后的去向；无法从结构化计划确定时明确显示未知。
7. 模块与 Initiative 的完成条件及其缺口，不输出百分比、ETA 或把任务数量当作总工作量。
8. Git 执行上下文：worktree 根目录、primary/linked 类型、分支或 detached HEAD、短 SHA、
   dirty 状态和模块 binding 证据。它不能被解释为任务领取或并行写入授权。
9. 风险、未知和冲突，以及每条关键结论的事实来源。

### Evidence rules

- `✓`：可读取的事实源满足确定条件；`~`：Spec/Plan/Task 声明了目标但尚无完成证据；
  `?`：缺失、不可访问或未结构化；`!`：来源冲突、依赖未满足或产物链断裂。
- 活跃 Initiative 只能由 `.agent/state.json.initiative` 与其 `map` 指向的能力图确认。
  身份不唯一、映射不一致或能力图不可解析时，不推断当前模块、下一动作或完成度。
- 任务范围仅展示当前任务中已声明的 `Files likely touched`。它是预估范围，不是 `git diff`
  的替代、实际修改清单或硬性白名单。
- `### Checkpoint` 及其结构化 checklist 可作为检查点事实；自由文本只能显示为“存在但无法确定
  条件/位置”，不得自行编号、标记通过或捏造最近检查点。
- `workflowStage: local-validation` 时，远端任务、Issue、PR/MR 与 binding 都是“不适用或未知”；
  路线图不得建议同步、领取、绑定或交付。

## Source precedence and Compatibility

| Fact | Authoritative source | Roadmap behavior |
|---|---|---|
| Module IDs and dependencies | Active `spec/CAPABILITY-MAP.md` | Parse with the existing strict capability-map parser. |
| Active Initiative and current module | `.agent/state.json` | Read only; never append roadmap state. |
| Compact phase classification | Existing `phase-guard` classifier | Keep its compact result separate; the roadmap does not parse its human-facing hook text. |
| Plan/checkpoint/task scope | Upstream module spec/plan and active task source | Show only declared, parseable facts. |
| Task/PR/MR state | Activated tracker bridge | Read on explicit roadmap request; read failure becomes `?`, never a false completion. |
| Worktree/branch/commit | Git | Use Git’s worktree and HEAD facts, independent of module identity. |

The implementation must not fork or modify upstream `agent-skills`, add fields to `.agent/state.json`, create a
parallel checkpoint schema, or write a new progress ledger. It must preserve the current local-validation and
paused-parallel safety gates.

## Commands

Planning and verification commands:

```text
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
python3 -B -m unittest discover -s plugins/spec-guard/hooks -p 'test_workflow_roadmap.py'
```

The roadmap itself must be invocable without network access. On an activated tracker, an explicit request may
attempt a read-only refresh; a failure must leave the local roadmap usable and label remote facts unknown.

## Project Structure and Style

- Deterministic collection/classification belongs in a small standard-library Python helper under
  `plugins/spec-guard/hooks/`; presentation instructions belong in `commands/` and `skills/spec-guard-ops/`.
- `phase-guard.sh` remains Bash 3.2 compatible and fast; it must not parse the full map/plan or call tracker APIs
  for automatic hook output.
- Tests use temporary Git repositories and tracker stubs. Assertions target individual output lines and structured
  fields, including negative cases, instead of broad substring matches.
- There is no browser UI in this module. The Plan must state that browser acceptance is not applicable unless a
  later task introduces a user-facing web surface.

## Boundaries

- Always: preserve all pre-existing dirty changes; distinguish verified facts from declared or unknown facts;
  keep roadmap reads side-effect free.
- Ask first: activating a tracker, changing an Initiative/module identity, changing the capability-map boundary,
  adding a dependency, or treating a checkpoint as human-approved.
- Never: create/close/update Issues, PRs, MRs or tasks; mutate `.agent/state.json`; infer completion from zero
  tasks; present a percentage/ETA; automatically inspect or control runtime ports, processes or data services;
  reactivate parallel writing.

## Success Criteria

- Users can locate the current module in the normal upstream lifecycle and distinguish it from plugin runtime
  mode, task state and Git context.
- `/phase` stays compact and offline; full maps appear only after an explicit roadmap request.
- A linked worktree and detached HEAD are displayed accurately, including their directory/commit context, while
  never being treated as a binding or permission.
- `--all` includes only modules from the uniquely identified active map and preserves graph dependencies.
- Missing task sources, tracker access, checkpoints, bindings or human review evidence degrade to `?`/`!`; no
  false completion or fabricated next step is emitted. A declared `Next step`/`下一步` is `~` navigation only,
  never execution or write authorization.
- Local-validation output remains local-only and does not recommend remote actions.
- Regression tests prove both normal and ambiguous/empty/unavailable cases, including that the renderer and
  command perform no writes.

## Open Questions

None for V1. Runtime port/process and semantic `git diff` scope analysis remain explicit non-goals and may only
be proposed as separate, opt-in diagnostics later.
