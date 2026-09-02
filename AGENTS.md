# AGENTS.md

本仓库的 agent 配置见 [CLAUDE.md](CLAUDE.md)。

作用域：配置在**本仓库**（spec-guard 插件源码）工作的 agent，
不是给使用者复制到自己项目里的。使用者需要的是
`plugins/spec-guard/templates/claude-block-*.md`，由 `/setup-convention` 写入。

<!-- BEGIN:spec-guard-codex-convention -->
## Spec Guard 项目约定

> 由 `setup-convention github --host=codex` 生成。

- 能力图：`spec/CAPABILITY-MAP.md`；模块 spec：`spec/<module-id>.md`
- 计划：`tasks/<module-id>/plan.md`；活跃模块和映射：`.agent/state.json`
- 任务事实源是 GitHub Issues；不要创建 `todo.md`
- 动 spec、拆任务、取任务或交付前，先加载 `spec-guard:spec-github-bridge` skill。
<!-- END:spec-guard-codex-convention -->
