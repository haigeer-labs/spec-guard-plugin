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

### issue types 可用性（决定加不加 `--type`）

读 `.agent/state.json` 的 `issueTypes`：

| 值 | 含义 | 怎么建 issue |
|---|---|---|
| `true` | 组织仓库，已启用 | 加 `--type Feature` / `--type Task` |
| `false` | **个人仓库**（issue types 是组织级功能） | **省略 `--type`**，其余不变 |

省略 `--type` 不影响任何流程：模块 issue 的 sub-issue **按构造就是 task**，层级本身已经编码了这个身份。`--parent`（层级）和
`--blocked-by`（依赖）在个人免费仓库上实测可用。

⚠️ **不要在 `issueTypes: false` 时硬加 `--type`** —— gh 会先把 issue 建出来
再报 `type "Task" not found`，**留下一个孤儿 issue**。实测确认过。

⚠️ 仍然**不要用 label 模拟 type** —— label 无层级、无依赖，筛选逻辑会全废。

---

## 操作一：能力图落库（bootstrap）

**输入**：`spec/CAPABILITY-MAP.md` 已经过人工评审
**输出**：Epic issue + N 个模块 issue + 依赖关系 + `.agent/state.json`

步骤：

1. 解析能力图的模块表和 build order
2. 创建 Epic（`issueTypes: false` 时去掉 `--type Feature` 这一行）：

       gh issue create --type Feature \
         --title "Initiative: <名称>" \
         --body-file spec/CAPABILITY-MAP.md

3. 按 build order 顺序，为每个模块创建 issue（同样，`issueTypes: false` 时去掉 `--type`）：

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

**输入**：`/plan` 产出的任务列表
**输出**：sub-issue + `plan.md` 的索引段

对每个 task（`issueTypes: false` 时去掉 `--type Task`）：

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

    MODULE_ISSUE=$(python3 -c "import json;d=json.load(open('.agent/state.json'));print(d['modules'][d['activeModule']]['issue'])")

    # ⚠️ 必须用 REST sub_issues。`gh issue list` **没有 --parent 这个 flag**
    #    （--parent 只在 gh issue create 上），用了会 unknown flag 直接失败。
    gh api "repos/{owner}/{repo}/issues/$MODULE_ISSUE/sub_issues"

    # 每个 task 的阻塞关系单独查：
    gh api "repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by"

筛选规则（按顺序）：

1. 排除 `issueType != Task` —— **`issueTypes: false` 时跳过这条**。
   `--parent <module>` 返回的按构造就是 task，这条规则本来就是冗余的
2. 排除 `state != "open"` —— REST 返回**所有状态**，不像 `gh issue list` 有 `--state`
3. 排除存在未关闭 `blocked-by` 的
4. 排除已有 assignee 且不是自己的（多人协作）
5. 取第一个

取到后：

    gh issue view <n> --json title,body,parent,dependencies
    gh issue edit <n> --add-assignee @me

把 issue 正文的验收标准交给 `/build`，替代它原本从 todo.md 读取的内容。

**如果当前模块没有可执行 task**：检查是否所有 task 都已关闭 → 若是，把该模块 issue 关闭，按 build order 推进 `activeModule`，写回 state.json。

---

## 操作四：交付（模块级 PR）

粒度是**模块**，不是 task。一个模块一条分支，跑完整个 plan 再收口。

模块开工时建一次分支：

    git checkout -b <type>/<module-id>

每完成一个 task 提交一次，**closing keyword 写在 commit message 里**：

    git commit -m "<type>(<scope>): <task 标题>

    Closes #<task-issue>"

模块的 task 全部落完、`/review` 通过后，开一个 PR：

    gh pr create \
      --title "<type>(<module-id>): <模块标题>" \
      --body "Closes #<module-issue>

    ## 落地的 task
    - #<n> <标题>
    - #<n> <标题>

    ## 验证
    <测试输出摘要>"

**合并只能用 merge commit 或 rebase。** squash 会把每条 commit message 压成一条，
task issue 除最后一个外全部留在 open —— 而 `/next` 会把它们当成没做完，
重新取出来做第二遍。

    gh pr merge --merge --delete-branch     # 或 --rebase

task issue 靠 commit message 关，module issue 靠 PR 正文关。两者都要到
**合入默认分支**才生效 —— 在特性分支上提交时 issue 不会动，这是正常的，
不是断链。

---

## Common Rationalizations

| 借口 | 反驳 |
|---|---|
| "先写 todo.md，之后再同步到 GitHub" | 两份真相源必然分叉。要么全在 GitHub，要么全在文件，不并存。 |
| "这个 task 很小，不用建 issue" | 小到不用建 issue 的 task，说明它不该是独立 task，合并到相邻 task 里。 |
| "依赖关系写在描述里更方便" | 写描述里 `/build` 读不到，无法自动跳过被阻塞的任务。必须用 --blocked-by。 |
| "直接关掉 issue 更快" | 手动关闭会丢失 PR ↔ issue 的关联，追溯时找不到实现在哪。 |
| "每个 task 开个 PR，交付更清楚" | 交付面被切碎，评审看不到一个需求的全貌，而每条都要停下来等合并。粒度对齐需求，不对齐提交。 |
| "PR 用 squash 合，历史干净" | squash 会吃掉每条 commit 的 `Closes #n`，只有最后一个 task issue 被关，其余全部留在 open。用 merge 或 rebase。 |
| "gh 版本低，用 label 模拟 type" | label 无层级、无依赖，`/build` 的筛选逻辑会全部失效。升级 gh。 |
| "个人仓库没有 issue types，那这套用不了" | 只有 `--type` 用不了。层级和依赖照常，省略 `--type` 即可，流程一步不少。 |
| "用 gh issue list --parent 列子任务" | **那个 flag 不存在**，只有 gh issue create 有 --parent。用 REST sub_issues。 |
| "反正建了也报错，先试试 --type" | 会留下孤儿 issue —— gh 先建后校验。读 `state.json` 的 `issueTypes`，别试。 |

## Red Flags

- 仓库里同时存在 `tasks/*/todo.md` 和对应的 GitHub sub-issue
- `plan.md` 的 Task List 是 checkbox 而不是 issue 编号
- issue 正文里粘贴了 spec 全文
- `.agent/state.json` 的 activeModule 和当前分支名不一致
- PR 描述里没有 `Closes #<module-issue>`
- 一个模块出现了多个 PR，或分支名里带 issue 号（说明退回了 task 级粒度）
- commit message 里没有 `Closes #<task-issue>`（那些 task issue 永远关不掉）

## Verification

每次操作后必须验证：

- bootstrap 后：`gh issue view <epic> --json subIssues` 返回的模块数 == 能力图的模块数
- 任务落库后：`gh api "repos/{owner}/{repo}/issues/<module-issue>/sub_issues"` 的条目数 == plan.md 索引条数
- 交付前：`git log <默认分支>..HEAD --format=%B | grep -c 'Closes #'` == 本模块要交付的 task 数
- 交付后：PR 页面显示 "Closes #<module-issue>" 的关联链接
- 合并后：本模块的 task issue 全部变 closed（若有残留 → 多半是被 squash 了）
