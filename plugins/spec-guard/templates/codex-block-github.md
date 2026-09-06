## Spec Guard 项目约定

> 由 `setup-convention github --host=codex` 生成。

- 能力图：`spec/CAPABILITY-MAP.md`；模块 spec：`spec/<module-id>.md`
- 计划：`tasks/<module-id>/plan.md`；活跃模块和映射：`.agent/state.json`
- 任务事实源是 GitHub Issues；不要创建 `todo.md`
- 动 spec、拆任务、取任务或交付前，先加载 `spec-guard:spec-github-bridge` skill。
- 阶段交接或停止时，加载 `spec-guard:spec-github-bridge` 的共享检查点规则，预告已授权下一步。
