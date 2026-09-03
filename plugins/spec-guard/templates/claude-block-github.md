## Agent Skills 集成约定

> 由 `/spec-guard:setup-convention github` 生成。**这里只留推导不出来的事实，「怎么做」在 `spec-github-bridge` skill 里。**
> 保留 `<!-- BEGIN/END -->` 标记（HTML 注释不进 context，是免费的），`/spec-guard:setup-convention --replace` 靠它升级本块。

- 任务的事实源是 **GitHub Issues**。**不要创建任何 `todo.md`**
- 能力图 `spec/CAPABILITY-MAP.md`，模块 spec `spec/<module-id>.md`（kebab-case，一次选定中途不改名）
- **不要**在项目根建 `SPEC.md` / `SPEC-<module>.md` —— `/build` 只认根 `SPEC.md`、
  `docs/SPEC.md`、`spec/` 三条路径，**只有第三条是通配的**
- 计划文档 `tasks/<module-id>/plan.md`；活跃模块与 issue 号在 `.agent/state.json`
- 分支是 `<type>/<module-id>`，**一个模块一条**，不是一个 task 一条

**动 spec、拆任务、取任务、交付之前，先加载 `spec-github-bridge` skill。**
上面五条是「放哪里」，skill 才有「怎么做」：issue 落库、`--parent` / `--blocked-by`、
归档标记、`/build auto` 连贯推进、模块级 PR 与合并策略。跳过它必然写出双真相源。
