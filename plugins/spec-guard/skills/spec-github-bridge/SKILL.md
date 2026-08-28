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

## 目录约定（硬约束 —— CLAUDE.md 里只写了结论）

| 放什么 | 路径 | 不能怎样 |
|---|---|---|
| 能力图 | `spec/CAPABILITY-MAP.md` | 未经人工评审不落 issue |
| 模块 spec | `spec/<module-id>.md` | kebab-case，**一次选定中途绝不改名**（改名 = state.json / issue / 分支三处同时失联） |
| 计划文档 | `tasks/<module-id>/plan.md` | 不共用 `tasks/plan.md`，多模块时会互相覆盖 |
| 任务清单 | **GitHub Issues** | **不创建任何 `todo.md`** —— 两份真相源必然分叉 |
| 项目状态 | `.agent/state.json` | `activeModule` + `modules.<id>.issue` |

**不要在项目根建 `SPEC.md` 或 `SPEC-<module>.md`。** `/build` 的 spec 查找规则只有三条
路径：根目录 `SPEC.md`、`docs/SPEC.md`、`spec/` 下的文件 —— **只有第三条是通配的**。
根目录的 `SPEC-identity.md` 它根本找不到，会当作「没有 spec」直接停下。

`plan.md` 的 Task List 章节**只放 issue 编号的有序索引，不重复 checklist**，开头注明
`> Tasks tracked in GitHub Issues #<module-issue>`。写成 checkbox 就是第二份真相源。

---

## 操作一：能力图落库（bootstrap）

**输入**：`spec/CAPABILITY-MAP.md` 已经过人工评审
**输出**：Epic issue + N 个模块 issue + 依赖关系 + `.agent/state.json`

步骤：

1. 解析能力图的模块表和 build order
2. 创建 Epic（`issueTypes: false` 时去掉 `--type Feature` 这一行）：

       gh issue create --type Feature \
         --title "Initiative: <名称>" \
         --body "能力图: \`spec/CAPABILITY-MAP.md\`

       <能力图目标段落摘要，3-5 行>"

   **不要 `--body-file spec/CAPABILITY-MAP.md`。** 那是把能力图全文灌进 Epic
   正文，和本节末尾那条「不要把 spec 全文复制进 issue 正文」是同一件事 ——
   能力图改了，Epic 正文不会跟着改，两份从此分叉。模块清单也不用抄：
   sub-issue 列表就是 GitHub 原生的那份索引，而且它一直是准的。

3. 按 build order 顺序，为每个模块创建 issue（同样，`issueTypes: false` 时去掉 `--type`）：

       gh issue create --type Feature \
         --parent <epic> \
         --title "<module-id>" \
         --body "Spec: \`spec/<module-id>.md\`（尚未撰写时也照写，这是它将来的位置）

       <该模块在能力图里那一行的职责描述，3-5 行>"

   摘要取自**能力图**，不是取自 `spec/<module-id>.md`。这一步跑的时候
   绝大多数模块的 spec **还不存在** —— hook 在只有第一个模块有 spec 时就叫
   `/sync-map`，而这一步要为全部 N 个模块建 issue。要是摘要必须来自各自的
   spec，这条流程从第二个模块起就无从执行。

   **整个操作一只依赖 `spec/CAPABILITY-MAP.md`，不依赖任何模块 spec。**
   所以它在能力图评审通过后的任何时刻都能跑，和「先写第一个模块的 spec」
   谁先谁后都不矛盾。

4. 按依赖表建立阻塞关系：

       gh issue edit <billing> --add-blocked-by <identity>

5. 全部建完后把 `activeModule` 设为 build order 的第一个，写回 `.agent/state.json`

**每建成一个 issue 就立刻写回 `.agent/state.json`，不要攒到最后一起写。**
Epic 建好写 `initiative.issue`，每个模块 issue 建好写 `modules.<id>.issue`。

理由是这一步**在外部系统上做不可逆的写入**，而它中途会失败：网络、限流、
`--type` 在个人仓库上被拒（本页陷阱表最后一行说的「孤儿 issue」就是它）、
用户按了停。攒到最后写的话，任何一次中途失败都留下
「GitHub 上已经建了 k 个 / `state.json` 干干净净」的状态，而
`/sync-map` 的前置判据读的正是 `initiative.issue` —— 它是空的，
于是重跑**从头再建一遍**，Epic 和模块 issue 各来一套。

增量写回之后重跑是可续的：`initiative.issue` 有值就跳过建 Epic，
`modules.<id>.issue` 有值就跳过该模块，只补没建成的那些。

> 重复建出来的 issue 可以 `gh issue delete` 删掉，但要先人工分辨哪套是哪套，
> 而且依赖关系和 sub-issue 层级都得重连。别把它当成兜底。

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

**每建成一个 task issue 就立刻把编号写进 `tasks/<module-id>/plan.md` 的
Task List，不要攒到最后一起回写。** 理由和操作一那条完全一样，
而这一步建的 issue 更多（一个模块 N 条）：中途失败（限流 / 网络 /
`--blocked-by` 指向还没建出来的 issue / 用户按停）就留下
「GitHub 建了 k 条 / plan.md 一条没记」，重跑于是把 k 条**再建一遍**。

重跑时：plan.md 的 Task List 里已经有编号的那几条跳过，只补没建的。

> 依赖用 `--blocked-by` 的话，**建的顺序要让前置先出生** ——
> 指向一个还不存在的编号会失败，而失败点之前建出来的 issue 已经留在仓库里了。

回写后 `tasks/<module-id>/plan.md` 的 Task List 章节形如：

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

筛选规则（按顺序）。**除第 3 条外全部只用上面这一次响应，不必逐个 task 再打 API**：

1. 排除 `state != "open"` —— REST 返回**所有状态**，不像 `gh issue list` 有 `--state`
2. 排除 `issue_dependencies_summary.blocked_by > 0` —— 这个字段数的就是
   **未关闭**的阻塞者，已关闭的不计（实测：某 task `total_blocked_by=1` 而
   `blocked_by=0`，因为那个前置 issue 已经关了）。答案已经在手里，
   不要为此逐个 task 打 `dependencies/blocked_by`
3. **排除本分支已经做完的** —— 模块级 PR 下 task issue 要到 PR 合入默认分支
   才关，做完的 task 在**整个模块周期里一直是 open**，前两条一条都挡不住它。
   少了这一条，`/next` 会把上一轮刚做完的那个原样再取出来做第二遍。

   号从 phase-guard 每轮注入的那行事实里直接读（「本分支已落 N 个 task 的
   commit（#11 #12）」）。拿不到时自己数：

       # 默认分支：先问 origin/HEAD（**不能只认 main/master** —— 默认分支叫
       # develop/trunk 的仓库上这条规则会一个号都拿不到），再退回本地 main/master，
       # 最后退回远端跟踪 ref。与两个 hook 的 default_base() 同一套顺序。
       N=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true); N="${N#origin/}"
       BASE=""
       for b in "${N}" main master; do
         [ -n "${b}" ] && git show-ref --verify --quiet "refs/heads/${b}" && { BASE="${b}"; break; }
       done
       [ -z "${BASE}" ] && [ -n "${N}" ] \
         && git show-ref --verify --quiet "refs/remotes/origin/${N}" && BASE="origin/${N}"
       [ -n "${BASE}" ] && git log -n 200 --format=%B "${BASE}..HEAD" \
         | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#[0-9]+' \
         | grep -oE '[0-9]+' | sort -u

   要的是**号的集合**，不是个数 —— 个数只够回答「模块做完没有」。
   拿这组号和 sub_issues **求交集**后排除；分支上出现的、不属于本模块的号
   （顺手修的别的 bug）本来就不在 sub_issues 里，交集会自动丢掉。

   **`<base>` 取不到（既没有 main 也没有 master）时这条规则不排除任何东西。**
   不能反过来全排 —— 那会在非常规默认分支名的仓库上一个 task 都取不到，
   而表现出来像「模块已经做完了」。
4. 排除已有 assignee 且不是自己的（多人协作）
5. 取第一个

需要知道**是谁**在挡（报给用户时）才单独查，只查那一个：

    gh api "repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by"

> 原先第一条是「排除 `issueType != Task`」。**REST `sub_issues` 的响应里
> 根本没有 type 字段**，那条规则在这份数据上无从判断；而 `--parent <module>`
> 返回的按构造就是 task，本来也是冗余的。已删。
> （核对边界：本账号只有个人仓库，`issueTypes` 不可用；有 issue types 的
> 组织仓库上该字段会不会出现，没验过。但即使出现，冗余这一点不变。）

取到后：

    # ⚠️ 字段是 `blockedBy`，**不是 `dependencies`** —— 后者会
    #    `Unknown JSON field` 直接失败。合法字段表：gh issue view <n> --json 乱写一个
    gh issue view <n> --json title,body,parent,blockedBy
    gh issue edit <n> --add-assignee @me

把 issue 正文的验收标准交给 `/build`，替代它原本从 todo.md 读取的内容。

**如果当前模块没有可执行 task**：检查是否所有 task 都已关闭 → 若是，把该模块 issue 关闭，按 build order 推进 `activeModule`，写回 state.json。

---

## 归档的任务清单

已完成模块的 `todo.md` 是**历史记录**，不是活的任务清单。检查器默认会把它当成
「与 tracker 并存」报违规 —— 那是误报，而**误报会让人关掉整个机制**。

豁免办法：在文件的**前 10 行**内写上 `已归档` 或 `ARCHIVED`：

    # Todo: <模块名>

    > ## ⚠️ 已归档 —— 任务级全部完成
    > 落地记录：issue #34 已关闭 · PR #36 已合入 main

只认前 10 行是刻意的 —— 避免正文里偶然提到「已归档」就被误判。
`phase-guard` 与 `verify-artifacts` 共用这条判据。

---

## 连贯推进一个模块（`/build auto`）

模块分支建好后用 `/build auto` 跑完整个模块，而不是 `/next` → `/build` 逐条停。
它只在开跑前要一次确认，之后每个 task 照样 RED → GREEN → 回归 → **单独 commit**，
去掉的是人在 task 之间的停顿，**不是验证**。

本约定下它的任务来源是 issue，不是 `plan.md` 的 checkbox（见操作三）：
按 sub_issues 顺序、跳过被 `blocked-by` 阻塞的，逐个做。

它会在这三种情况停下来问，**别绕过** —— 那是这条流水线上仅剩的刹车：
测试改不红 / 构建坏了、spec 没覆盖到的决策、高风险不可逆的改动。

---

## 切换模块

切换 `activeModule` 前，当前模块必须没有 in-progress 的 task。
切换后**重读**该模块的 `spec/<module-id>.md` 和 `tasks/<module-id>/plan.md` ——
不重读的话，你手里还是上一个模块的上下文。

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

**合并只能用 merge commit 或 rebase。** 理由不是「squash 会漏关 issue」——
GitHub 的 squash 默认（`squash_merge_commit_message: COMMIT_MESSAGES`）会把每条
commit message 拼进压缩后的正文，closing keyword 通常还在。真正的理由是：

1. 那个拼接依赖一个**可改的仓库设置**，合并对话框里的正文也能手改 ——
   task issue 关不关取决于一个没人盯着的开关，而漏关的表现是 `/next`
   把已完成的 task 重新取出来做第二遍。**注意这是合并之后的那一份重取**；
   合并之前的同名症状是另一回事，由操作三的筛选规则 3 挡
2. `/build auto` 刻意做到一个 task 一条 commit，为的是**任意一点都能干净回滚**；
   squash 压成一条后只能整个模块一起 revert

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
| "PR 用 squash 合，历史干净" | 干净的代价是丢掉一 task 一 commit 的回滚点，出事只能整个模块一起 revert。closing keyword 多半还在（默认拼接 commit messages），但那是个可改的设置，不该拿它当保证。 |
| "gh 版本低，用 label 模拟 type" | label 无层级、无依赖，`/build` 的筛选逻辑会全部失效。升级 gh。 |
| "个人仓库没有 issue types，那这套用不了" | 只有 `--type` 用不了。层级和依赖照常，省略 `--type` 即可，流程一步不少。 |
| "用 gh issue list --parent 列子任务" | **那个 flag 不存在**，只有 gh issue create 有 --parent。用 REST sub_issues。 |
| "反正建了也报错，先试试 --type" | 会留下孤儿 issue —— gh 先建后校验。读 `state.json` 的 `issueTypes`，别试。 |
| "issue 都建完了再一次性写 state.json，省事" | 中途失败就留下「GitHub 建了一半 / state.json 全空」，而重跑的判据读的就是 state.json —— 于是从头再建一套。每建成一个立刻写回。 |
| "task issue 都建完了再一次性回写 plan.md" | 同上，只是这次记录落在 plan.md 的 Task List 上，而且一个模块建 N 条，中途失败的窗口更大。每建成一个立刻写编号。 |

## Red Flags

- 仓库里同时存在 `tasks/*/todo.md` 和对应的 GitHub sub-issue
- `plan.md` 的 Task List 是 checkbox 而不是 issue 编号
- issue 正文里粘贴了 spec 全文
- `.agent/state.json` 的 activeModule 和当前分支名不一致
- PR 描述里没有 `Closes #<module-issue>`
- 一个模块出现了多个 PR，或分支名里带 issue 号（说明退回了 task 级粒度）
- 同一个 initiative 在 GitHub 上有两个 Epic，或同名模块 issue 出现两次
  （`/sync-map` 中途失败后重跑的典型残留）
- 模块 issue 下同一个 task 标题出现两次（任务落库中途失败后重跑的残留）
- `plan.md` 有 Task List 但模块 issue 下**一个 sub-issue 都没有** ——
  任务从没落库。`phase-guard` 会把它判成 `PLANNED (任务未落库)`；
  它跟「任务全部做完」在「未关闭数=0」上长得一样，别混
- commit message 里没有 `Closes #<task-issue>`（那些 task issue 永远关不掉）

## Verification

每次操作后必须验证：

- bootstrap 后：`gh issue view <epic> --json subIssues -q '.subIssues.totalCount'` == 能力图的模块数
  （`subIssues` 返回的是 `{nodes, totalCount}` 对象，不是裸数组 —— 直接 `| length` 会得到 `2`）
- 任务落库后：`gh api "repos/{owner}/{repo}/issues/<module-issue>/sub_issues"` 的条目数 == plan.md 索引条数
- 交付前：`git log <默认分支>..HEAD --format=%B | grep -c 'Closes #'` == 本模块要交付的 task 数
- 交付后：PR 页面显示 "Closes #<module-issue>" 的关联链接
- 合并后：本模块的 task issue 全部变 closed（有残留 → 查合并时落到默认分支的正文里 closing keyword 还在不在）
