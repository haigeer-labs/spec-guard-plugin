---
name: spec-github-bridge
description: 在 agent-skills 的 spec/plan 产物和 GitHub Issues 之间同步。
  当需要把能力图落成 issue、取下一个任务、或交付一个任务时使用。
---

## 前置检查

必须先确认：

    gh --version        # ≥ 2.94.0（低于此版本没有 --type / --parent / --blocked-by）
    gh auth status
    test -f .agent/state.json

版本不足直接停下并告知用户，不要退化用 label 模拟 issue type。

---

## 操作一：能力图落库（bootstrap）

**输入**：`spec/CAPABILITY-MAP.md` 已经过人工评审
**输出**：Epic issue + N 个模块 issue + 依赖关系 + `.agent/state.json`

步骤：

1. 解析能力图的模块表和 build order
2. 创建 Epic：

       gh issue create --type Feature \
         --title "Initiative: <名称>" \
         --body-file spec/CAPABILITY-MAP.md

3. 按 build order 顺序，为每个模块创建 issue：

       gh issue create --type Feature \
         --parent <epic> \
         --title "<module-id>" \
         --body "Spec: \`spec/<module-id>.md\`

       <spec 的 objective 段落摘要，3-5 行>"

4. 按依赖表建立阻塞关系：

       gh issue edit <billing> --add-blocked-by <identity>

5. 写 `.agent/state.json`，`activeModule` 设为 build order 的第一个

**不要**把 spec 全文复制进 issue 正文——spec 会改，复制会分叉。

---

## 操作二：任务落库（planning 之后）

**输入**：`/planning` 产出的任务列表
**输出**：sub-issue + `plan.md` 的索引段

对每个 task：

    gh issue create --type Task \
      --parent <module-issue> \
      --title "<task 标题>" \
      --body "$(cat <<'EOF'
    ## 验收标准
    - [ ] ...

    ## 验证步骤
    1. ...

    ## 上下文
    Spec: `spec/<module-id>.md`
    Plan: `tasks/<module-id>/plan.md`
    EOF
    )"

有先后依赖的：

    gh issue create ... --blocked-by <前置 issue>

创建完成后，回写 `tasks/<module-id>/plan.md` 的 Task List 章节：

    ## Task List
    > Tasks tracked in GitHub Issues #<module-issue>

    ### Phase 1: Foundation
    - #110 建立 session 表结构
    - #111 实现 token 签发（blocked by #110）

    ### Checkpoint
    - #112 Checkpoint: 端到端登录跑通

---

## 操作三：取下一个任务

    MODULE_ISSUE=$(jq -r '.modules[.activeModule].issue' .agent/state.json)
    gh issue list --parent $MODULE_ISSUE --state open \
      --json number,title,issueType,dependencies

筛选规则（按顺序）：

1. 排除 `issueType != Task`
2. 排除存在未关闭 `blocked-by` 的
3. 排除已有 assignee 且不是自己的（多人协作）
4. 取第一个

取到后：

    gh issue view <n> --json title,body,parent,dependencies
    gh issue edit <n> --add-assignee @me

把 issue 正文的验收标准交给 `/build`，替代它原本从 todo.md 读取的内容。

**如果当前模块没有可执行 task**：检查是否所有 task 都已关闭 → 若是，把该模块 issue 关闭，按 build order 推进 `activeModule`，写回 state.json。

---

## 操作四：交付

`/review` 通过后：

    git checkout -b <type>/<issue>-<slug>
    # ... commits ...
    gh pr create \
      --title "<type>: <task 标题>" \
      --body "Closes #<issue>

    ## 变更
    <一句话>

    ## 验证
    <测试输出摘要>"

**PR 正文必须含 `Closes #<n>`**，否则 issue 不会自动关闭、Project 看板不会流转。

---

## Common Rationalizations

| 借口 | 反驳 |
|---|---|
| "先写 todo.md，之后再同步到 GitHub" | 两份真相源必然分叉。要么全在 GitHub，要么全在文件，不并存。 |
| "这个 task 很小，不用建 issue" | 小到不用建 issue 的 task，说明它不该是独立 task，合并到相邻 task 里。 |
| "依赖关系写在描述里更方便" | 写描述里 `/build` 读不到，无法自动跳过被阻塞的任务。必须用 --blocked-by。 |
| "直接关掉 issue 更快" | 手动关闭会丢失 PR ↔ issue 的关联，追溯时找不到实现在哪。 |
| "gh 版本低，用 label 模拟 type" | label 无层级、无依赖，`/build` 的筛选逻辑会全部失效。升级 gh。 |

## Red Flags

- 仓库里同时存在 `tasks/*/todo.md` 和对应的 GitHub sub-issue
- `plan.md` 的 Task List 是 checkbox 而不是 issue 编号
- issue 正文里粘贴了 spec 全文
- `.agent/state.json` 的 activeModule 和当前分支名不一致
- PR 描述里没有 `Closes #`

## Verification

每次操作后必须验证：

- bootstrap 后：`gh issue view <epic> --json subIssues` 返回的模块数 == 能力图的模块数
- 任务落库后：`gh issue list --parent <module> --json number | jq length` == plan.md 索引条数
- 交付后：PR 页面显示 "Closes #n" 的关联链接
