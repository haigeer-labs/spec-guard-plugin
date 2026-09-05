# Implementation Plan: desktop-worker-registration

## Overview

让用户已经在 Codex Desktop 或 Claude Code Desktop 创建的原生 linked worktree，可以在不接管
宿主生命周期的前提下安全登记进既有并行 run；任何无法从实际 cwd、Git 元数据和稳定宿主 ID
证明的 worker 都保持未登记。

> Tasks tracked in GitHub Issues #99。

## Architecture Decisions

- Desktop worker 使用独立的 host-owned manifest；其 `owner=host` 与 controller 创建的
  `owner=spec-guard` 严格区分，不能复用受控删除路径。
- 登记只基于实际 cwd 的 common-dir、base SHA、branch、linked-worktree 和 module lease；标题、
  sidebar 文案、pending ID 或推测目录绝不能充当身份。
- Codex Desktop 与 Claude Desktop 都是 register-only：插件不创建、归档、隐藏或删除 Desktop
  session/worktree；宿主 API 缺失时输出手工步骤。

## Dependency Graph

```text
host manifest + Git identity registration
              ↓
register command + status/reclaim host handling
              ↓
Desktop documentation + real E2E evidence
              ↓
final checkpoint
```

## Task List

### Phase 1: Host identity foundation

- #132 实现 Desktop host worker 的受控登记运行时

### Phase 2: Explicit operator workflow

- #133 实现 Desktop worker 登记命令与安全状态呈现（blocked by #132）

### Phase 3: Host evidence and documentation

- #134 补充 Desktop 接入文档并执行原生 E2E 验证（blocked by #133）

### Final checkpoint

- #135 Checkpoint: 验证 Desktop worker register-only 工作流（blocked by #132, #133, #134）

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Desktop UI 名称或 pending ID 被误用为身份 | 只接受稳定 host ID 和实际 cwd 的 Git 证据。 |
| host-owned 资源被 CLI 回收器删除 | manifest owner 分离；回收命令只显示宿主可回收状态。 |
| Desktop worktree 处于 detached HEAD 或非 linked checkout | 拒绝登记并给出手工排查指引。 |
