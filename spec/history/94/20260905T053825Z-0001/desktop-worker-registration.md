# Spec: desktop-worker-registration

## Objective

让用户在 Codex Desktop 或 Claude Code Desktop 中已经创建的原生 Worktree worker 能安全加入
并行 run。该模块只登记与校验，不承诺创建、隐藏、关闭或删除 Desktop 子任务。

## Tech Stack

- Python 3 标准库：manifest/ledger 校验和受控登记。
- Git：验证 cwd、common-dir、HEAD、branch 和 linked-worktree 身份。
- Markdown command/skill：展示宿主差异、登记步骤与可回收状态。

## Commands

```text
/parallel-register-worker <run-id> <module-id> --host codex-desktop
/parallel-register-worker <run-id> <module-id> --host claude-desktop
/parallel-status <run-id>
```

## Interface Contract

登记必须从 Desktop worker 的实际 cwd 读取 Git 数据，并与 run 的 common-dir、base SHA、module
lease 逐项匹配。stable host worker ID 不可得时，登记失败且只给出手工步骤；不能用标题猜测
身份。成功记录 owner=`host`，因此 `/parallel-reclaim` 只能显示“可由用户/宿主回收”，不能调用
`git worktree remove` 或 Desktop archive。

Codex Desktop 的公开 App Server 只支持指定 `cwd` 的通用线程，未公开 managed-worktree 创建
字段；本模块不能调用本研究会话的宿主特权 API 作为产品能力。Claude Desktop 的自动隔离也需
以实际 cwd 实证，不把 UI 文案当成隔离证明。

## Project Structure

```text
plugins/spec-guard/hooks/parallel-desktop-register.py
plugins/spec-guard/commands/parallel-register-worker.md
plugins/spec-guard/skills/spec-guard-ops/SKILL.md
plugins/spec-guard/hooks/test-desktop-worker-registration.sh
docs/claude-desktop.md
README.md
```

## Testing Strategy

- Git 夹具覆盖 host worker 的 common-dir、HEAD、module/lease 不匹配拒绝。
- Codex/Claude Desktop 真实 E2E 各自验证：创建的原生 session、cwd、状态登记、停止/归档后状态。
- 缺 host ID/API、detached HEAD、submodule 或 pending session 必须 fail closed。
- 登记与状态标记不删除 Desktop/用户 worktree。

## Boundaries

- Always: 将 host 和 Spec Guard 的所有权明确区分；展示登记不等于自动管理。
- Ask first: 任何宿主标题更新、handoff、archive 或 UI 生命周期操作。
- Never: 用 `git worktree add` 冒充 Desktop managed task；回收 owner=host 的资源；静默创建 sidebar task。

## Success Criteria

1. 只有实际属于当前 run 和模块的原生 Worktree 可登记。
2. 不具备可验证宿主能力时安全降级为手工指导。
3. 插件绝不删除或隐藏用户/宿主创建的 Desktop 任务。

## Parallel Boundary

```json
{
  "paths": ["plugins/spec-guard/hooks/parallel-desktop-register.py", "plugins/spec-guard/commands/parallel-register-worker.md", "plugins/spec-guard/skills/spec-guard-ops/SKILL.md", "plugins/spec-guard/hooks/test-desktop-worker-registration.sh", "docs/claude-desktop.md", "README.md"],
  "publicInterfaces": ["parallel-desktop-registration-v1"],
  "migrations": [],
  "globalConfig": [],
  "testResources": []
}
```
