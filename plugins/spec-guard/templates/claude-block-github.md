## Agent Skills 集成约定

> 本块由 `/setup-convention github` 生成。任务托管在 **GitHub Issues**。
> 修改时保留 `<!-- BEGIN/END:agent-skills-convention -->` 标记，便于工具识别。

### Spec 布局（多模块）

- 能力图：`spec/CAPABILITY-MAP.md`
- 模块 spec：`spec/<module-id>.md`（kebab-case，一次选定，中途绝不改名）
- **不要**在项目根创建 `SPEC.md` 或 `SPEC-<module>.md`

  原因：`/build` 的 spec 查找规则只有三条路径——根目录 `SPEC.md`、`docs/SPEC.md`、
  `spec/` 下的文件。**只有第三条是通配的**，根目录的 `SPEC-identity.md` 它找不到。

### Planning 产物

- 计划文档：`tasks/<module-id>/plan.md`
- **不要创建任何 todo.md**

本项目使用 **GitHub Issues 作为 task list target**。planning 阶段：

- 每个 task 用 `gh issue create --type Task --parent <module-issue>` 创建
  - `.agent/state.json` 的 `issueTypes` 为 `false` 时**省略 `--type`**（个人仓库没有
    issue types，那是组织级功能）。层级本身已区分 task，流程不受影响
- 验收标准和验证步骤写进 issue 正文
- 依赖关系用 `--blocked-by <n>`，不要写在描述里
- checkpoint 也建 issue，标题以 `Checkpoint:` 开头
- `plan.md` 开头注明 `> Tasks tracked in GitHub Issues #<module-issue>`
- `plan.md` 的 Task List 章节只放 issue 编号的有序索引，不重复 checklist

### Build 输入源

`/build` 取下一个任务时，**不要读 todo.md**，改为：

1. 读 `.agent/state.json` 确认 `activeModule`
2. `gh api "repos/{owner}/{repo}/issues/<module-issue>/sub_issues"`
   （**不是** `gh issue list --parent` —— 那个 flag 不存在，只有 `gh issue create` 有）
   REST 返回所有状态，自己筛 `state == "open"`
3. 跳过所有存在未关闭 `blocked-by` 的 issue
4. 取第一个可执行的 Task

### Build 输出

1. 分支名：`<type>/<issue-number>-<slug>`
2. `gh pr create --body "Closes #<issue-number>"`
3. **不要手动关闭 issue**，靠 PR 合并触发

### 切换模块

切换 `activeModule` 前，当前模块必须没有 in-progress 的 task。
切换后重读该模块的 `spec/<module-id>.md` 和 `tasks/<module-id>/plan.md`。
