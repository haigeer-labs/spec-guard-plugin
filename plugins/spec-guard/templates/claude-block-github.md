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

### 归档的任务清单

已完成模块的 `todo.md` 是**历史记录**，不是活的任务清单。在**前 10 行**内写上
`已归档` 或 `ARCHIVED`，检查器就会把它从「与 tracker 并存」和「命名空间」
两项检查里排除：

```markdown
# Todo: <模块名>

> ## ⚠️ 已归档 —— 任务级全部完成
> 落地记录：issue #34 已关闭 · PR #36 已合入 main
```

只认前 10 行是刻意的 —— 避免正文里偶然提到「已归档」就被误判。

### Build 输入源

`/build` 取下一个任务时，**不要读 todo.md**，改为：

1. 读 `.agent/state.json` 确认 `activeModule`
2. `gh api "repos/{owner}/{repo}/issues/<module-issue>/sub_issues"`
   （**不是** `gh issue list --parent` —— 那个 flag 不存在，只有 `gh issue create` 有）
   REST 返回所有状态，自己筛 `state == "open"`
3. 跳过所有存在未关闭 `blocked-by` 的 issue
4. 取第一个可执行的 Task

### 连贯推进一个模块

模块分支建好后，用 `/build auto` 跑完整个模块，而不是 `/next` → `/build` 逐条停。
它只在开跑前要一次确认，之后每个 task 照样 RED → GREEN → 回归 → 单独 commit，
**去掉的是人在 task 之间的停顿，不是验证**。

在本约定下它的任务来源是 issue 不是 plan.md 的 checkbox（见上「Build 输入源」）：
按 sub_issues 的顺序、跳过被 `blocked-by` 阻塞的，逐个做。

`/build auto` 会在这几种情况停下来问：测试改不红/构建坏了、spec 没覆盖到的决策、
以及高风险不可逆的改动。**别绕过它们** —— 那是这条流水线上仅剩的刹车。

### Build 输出（模块级 PR）

**一个模块一条分支一个 PR，不是一个 task 一个 PR。**

1. 分支名：`<type>/<module-id>`（模块开工时建一次，整个模块都在它上面）
2. 每完成一个 task 提交一次，commit message 里带 `Closes #<task-issue>`
3. 模块的 task 全部落完，再 `gh pr create --body "Closes #<module-issue>"`
4. 合并**必须用 merge commit 或 rebase，不能 squash**
5. **不要手动关闭 issue**，靠合并触发

第 2 条能关 issue 是因为 closing keyword 在 commit message 里同样生效 ——
官方原话是 the issue will be closed when you merge the commit into the
**default branch**。

第 4 条的理由**不是**「squash 会漏关 issue」。GitHub 的 squash 默认配置
（`squash_merge_commit_message: COMMIT_MESSAGES`）会把每条 commit message
拼进压缩后的正文，那些 `Closes #n` 通常还在、照样生效。真正的理由是两条：

- 那个拼接**依赖一个可改的仓库设置** —— 换成 `PR_BODY` 就全丢，合并对话框里的
  正文也随时能手改。task issue 关不关，取决于一个没人盯着的开关
- `/build auto` 刻意做到**一个 task 一条 commit**，为的是任意一点都能干净回滚。
  squash 把 N 条压成一条，这个性质当场消失 —— 出事只能整个模块一起 revert

> 想知道自己这个仓会不会吃掉 closing keyword：
> `gh api repos/{owner}/{repo} --jq .squash_merge_commit_message`

为什么不一个 task 一个 PR：task 拆得越细 PR 越碎，一个需求被切成 N 个互不相干的
合并事件 —— 评审时看不到完整交付面，做的人每条都要停下来等合并。**PR 的粒度对齐
「一个需求」，不是「一次提交」。**

例外（这时仍然单开 PR）：task 本身独立可发布（hotfix、改配置），
或模块大到一条分支要活过 3 天 —— 后者说明模块该拆，上游 git-workflow-and-versioning
的原话是 long-lived branches are the problem, merge within 1-3 days。

### 切换模块

切换 `activeModule` 前，当前模块必须没有 in-progress 的 task。
切换后重读该模块的 `spec/<module-id>.md` 和 `tasks/<module-id>/plan.md`。
