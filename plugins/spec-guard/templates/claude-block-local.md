## Agent Skills 集成约定

> 本块由 `/setup-convention local` 生成。任务托管在**本地 todo.md**（Addy 原生路径）。

### Spec 布局（多模块）

- 能力图：`spec/CAPABILITY-MAP.md`
- 模块 spec：`spec/<module-id>.md`（kebab-case，一次选定，中途绝不改名）
- **不要**在项目根创建 `SPEC.md` 或 `SPEC-<module>.md`

### Planning 产物

- 计划文档：`tasks/<module-id>/plan.md`
- 任务清单：`tasks/<module-id>/todo.md`

每个模块的产物互相隔离，不要共用 `tasks/plan.md`。

### Build 输入源

1. 读 `.agent/state.json` 确认 `activeModule`
2. 从 `tasks/<activeModule>/todo.md` 取第一个未勾选任务
3. 不要跨模块取任务

### 切换模块

切换 `activeModule` 前，当前模块必须没有进行中的 task。
切换后重读该模块的 spec 和 plan。
