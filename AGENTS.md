# AGENTS.md

本仓库的 agent 配置见 [CLAUDE.md](CLAUDE.md)。

作用域：配置在**本仓库**（spec-guard 插件源码）工作的 agent，
不是给使用者复制到自己项目里的。使用者需要的是
`plugins/spec-guard/templates/claude-block-*.md`，由 `/setup-convention` 写入。

<!-- BEGIN:spec-guard-codex-convention -->
## Spec Guard 项目约定

> 本仓库正在进行独立的 legacy tracker bridge 退役迁移；不要把 Proposal
> 生命周期或 `.agent/state.json` 当作迁移状态。

- 能力图：`spec/CAPABILITY-MAP.md`；模块 spec：`spec/<module-id>.md`
- Proposal 共享事实只来自远端默认分支；GitHub/GitLab 仅可作为只读 Proposal Issue 来源。
- Proposal 不调用旧 tracker bridge，不创建或修改 Issue、PR、分支、任务或 `.agent/state.json`。
- 退役 Spec 与 Plan 位于 `docs/retirements/`，不加入当前 Proposal capability map。
<!-- END:spec-guard-codex-convention -->
