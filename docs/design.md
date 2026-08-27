# 设计文档：为什么需要 spec-guard

本文是 spec-guard 的需求与设计依据。所有结论来自对 `addyosmani/agent-skills`
仓库（187 个文件）的逐文件核对，不是推测。

---

## 一、问题陈述

`addyosmani/agent-skills` 是一套优秀的工程流程 skill 集合，但在三个场景下会失效：

### 场景 1：多需求并行时产物互相覆盖

`spec-driven-development` 的 **Phase 0** 支持多模块——检测到一个需求包含多个
独立可测能力时，会产出能力图并按 module id 生成 `SPEC-identity.md`、
`SPEC-billing.md`。

**但下游没跟上：**

```
/spec     ✅ 多模块：能力图 + SPEC-<module>.md
/plan ❌ 单例：  tasks/plan.md、tasks/todo.md（无命名空间）
/build    ❌ 单例：  "从 plan 里取下一个 pending task"
```

四个模块递归跑下来，第二个模块的 `/plan` 会覆盖第一个的 `tasks/plan.md`。

### 场景 2：spec 放在根目录时 `/build` 找不到

`commands/build.toml` 第 30 行的原文规则：

> **Require a spec.** 只在已知路径找 spec：仓库根的 `SPEC.md`、`docs/SPEC.md`、
> 或 `spec/` 下的文件。README 或任意文档不算。

三条路径里 **只有第三条是通配的**。Phase 0 生成的 `SPEC-identity.md` 放在根目录，
恰好落在匹配范围之外。

**这是上游内部的一处不一致**：多 spec 的命名约定和多 spec 的查找规则对不上。

### 场景 3：链路走一半断了

`docs/agents.md` 第 22 行和第 55 行：

> **The user (or a slash command) is the orchestrator.**
> ...
> Sequential slash commands **run by the user**（/spec → /plan → /build → /test → /review）

**顺序编排的责任被显式交给了人。** 没有任何机制推进状态机——`/spec` 跑完不会
叫 `/plan`，`/plan` 跑完不会叫 `/build`。

所以「产生了 spec 但没建 task」不是 bug，是设计使然。

---

## 二、上游已经留好的扩展点

核对源码时发现一件事：**GitHub 集成的接口，作者已经设计好了，只是没写实现。**

`skills/planning-and-task-breakdown/SKILL.md` 的 **Output Files → Task List Target**：

> - **默认：`tasks/todo.md` 的 checklist 式 markdown 文件。**这是 `/build` 命令和
>   其他下游工具期望的约定。除非项目另有规定，否则用它。
> - **外部 tracker：**如果项目的 agent 规则（`CLAUDE.md`、`AGENTS.md` 等）或用户
>   指定了 issue tracker（GitHub Issues、Jira、Linear、`bd`/beads），就**为每个 task
>   创建一个 tracker 条目，而不是写 `tasks/todo.md`**。把 Step 4 的结构映射到
>   tracker 的字段上：验收标准和验证步骤放进条目正文，依赖关系用 tracker 的链接
>   机制（`bd dep add`、"blocked by" 等）。

三条关键设计（都很讲究）：

1. **plan.md 永远是 markdown，不进 tracker** —— 原文理由：*设计决策、风险和开放
   问题无法干净地映射到单个 tracker issue 上*
2. **todo.md 和 tracker 二选一，不并存** —— 原文用词是 `instead of`，不是
   `in addition to`
3. **plan.md 要记录 tracker 位置** —— 这是跨会话续接的锚点

**全仓库搜索确认：除了这段说明，没有任何 `gh issue` / `gh pr` 的实际调用。**
（`AGENTS.md`、`CONTRIBUTING.md` 里的 `gh pr list --state open` 是给贡献者查重用的，
与工作流无关。）

作者在 `docs/comparison.md` 里评价竞品 Superpowers 时也提到：

> 最近的工作正在把它从单会话 skill 推向**通过 issue tracker 做多会话编排**
> （进行中的 `wayfinder`）。

**作者知道这个方向，但自己这套还停在单会话模型。**

---

## 三、五个缺口与对策

| # | 缺口 | 对策 | 是否需要写代码 |
|---|---|---|---|
| A | `/build` 找不到多 spec | spec 放 `spec/` 目录，利用既有通配 | ❌ 只是约定 |
| B | plan/todo 跨模块覆盖 | 按 module id 加命名空间 | ❌ 只是约定 |
| C | task 没托管到 tracker | `CLAUDE.md` 声明激活内置分支 | ❌ 只是声明 |
| D | `/build` 不知道去 tracker 取任务 | `CLAUDE.md` 里重定向输入源 | ❌ 只是声明 |
| E | 没有 PR 创建和状态回写 | `spec-github-bridge` skill | ✅ |
| F | 跨会话不知道做到哪 | `.agent/state.json` + hook 探测 | ✅ |

**A-D 全部靠约定解决，不改上游一行代码。** 真正要写的只有 E 和 F。

---

## 四、核心设计决策

### 决策 1：状态注入，不是意图分类

「说了需求但没触发对应 skill」的直觉解法是加一层路由 skill。**这行不通** ——
路由 skill 自己也要靠 description 触发，是同一个问题。

改为注入**确定性事实**：

```
文件在不在？   → 确定
issue 有没有？ → 确定
分支干不干净？ → 确定
```

模型看得见缺什么，路由自然就准。而且断链在下一轮对话开头就暴露。

| | 路由 skill | 状态注入 hook |
|---|---|---|
| 触发可靠性 | 靠 description 匹配 —— 同样的问题 | 100%，hook 强制执行 |
| 断链检测 | 只在被调用时 | 每次发言 |
| 上下文成本 | 整个 skill 常驻 | ~200 token |
| 出错影响 | 跑错流程 | 最坏多说一段状态 |

### 决策 2：不 fork 上游

所有定制走 `CLAUDE.md` 声明和本插件自己的文件。上游更新时不会断。

### 决策 3：tracker 无关

早期版本把 GitHub 绑死在约定里，导致 **GitLab 项目永远误报「没建 issue」**。

**假断链比不报断链危害大得多** —— 它会让人几天内就关掉整个机制，连带把真正
有用的检测一起丢掉。

现在的判定顺序：`state.json` 的 `tracker` 字段 → git remote 域名推断 → `none`。

| 模式 | 任务清单在哪 | 检测范围 |
|---|---|---|
| `github` | GitHub Issues | 完整（含任务层） |
| `none` | `tasks/<module>/todo.md` | 完整（上游原生路径） |
| `other` / `gitlab` / `jira` | 你自己的系统 | 只到 plan 层 |

**目录约定三种模式完全一样**，只有任务层落点不同。所以从 `none` 迁到 `github`，
`spec/` 和 `plan.md` 一个字不用改。

### 决策 4：探测失败就降级

`gh` 没装 / 没登录 / 离线 → 退化为本地判定，阶段名标注 `(gh 不可用，降级判定)`，
**不报 GitHub 相关断链**。

### 决策 5：插件 + 一个 setup 命令

插件不能往用户仓库写文件，但 `CLAUDE.md` 声明块必须提交进仓库（否则队友不生效）。
所以拆成：

```
插件      = 装给「你这台机器」的工具   · 每人各装各的
项目约定  = 提交给「整个项目」的规范   · 全队共享
```

`/setup-convention` 是把两者接起来的那一步。

0.7.0 补了两个开关：`--replace`（已装的声明块就地升级到当前模板，只动
`BEGIN`/`END` 之间）和 `--no-claude-md`（完全不写声明块）。前者是必需的 ——
没有它老用户没法迁移，原来遇到已存在的块是直接跳过的。

### 决策 6：声明块只放事实，过程进 skill

**0.7.0 把 CLAUDE.md 声明块从 106 行砍到 15 行。**

起因是实测数字：接入后使用者项目的 `CLAUDE.md` 321 行，声明块占 108 行 = 34%。
而官方对 CLAUDE.md 的原话是 *target under 200 lines per CLAUDE.md file. Longer
files consume more context and reduce adherence.*

排掉过一个看起来最顺手的方案：**`@path` import 省不了行数**。官方明说
*splitting into imports helps organization but doesn't reduce context, since
imported files load at launch* —— 它只解决维护。

`.claude/rules/` + `paths:` 前缀作用域也没采用：它在 Claude **读到**匹配文件时才
触发，而「不要在根目录建 `SPEC.md`」恰恰要在还没读任何文件时就知道。

采用的是官方自己给的正解 —— *If an entry is a multi-step procedure or only
matters for one part of the codebase, move it to a **skill** or a path-scoped
rule instead.* 那 106 行绝大部分是「怎么做」，现在全在 `spec-github-bridge`
skill 里按需加载。

留在 CLAUDE.md 里的只有两样：

1. **推导不出来的事实** —— 路径、tracker 类型、几条硬禁令
2. **一句触发指令** —— 动 spec / 拆任务 / 取任务 / 交付之前先加载 skill

**第 2 条不能省。** skill 是按需加载的，不写死的话模型可能在没加载 skill 的情况下
就把 `SPEC.md` 建到根目录 —— 而那正是这个声明块当初存在的理由。

配套：hook 的激活信号从「只认 CLAUDE.md 标题」扩成「标题 **或** `.agent/state.json`
存在」，让选 `--no-claude-md` 的项目也认得出自己管的仓库。`.agent/` 是本插件
自己的目录，拿它当信号不违反「默认不生效」那条不变量。

顺带两个免费的发现：HTML 注释**不进 context**（官方：*block-level HTML comments
are stripped before the content is injected*），所以 `BEGIN`/`END` 标记不计成本，
给人看的维护说明也可以塞进注释；以及**知识可以放进报错文案** —— 「归档豁免」
原先占 15 行常驻 context，现在只在真报「`todo.md` 与 tracker 并存」时才花。

---

## 五、对象模型

```
Issue #100  [Feature]  Initiative: 用户体系重构        ← 能力图
  │
  ├─ Issue #101  [Feature]  identity                  ← spec/identity.md
  │    ├─ Issue #110  [Task]  建立 session 表结构
  │    ├─ Issue #111  [Task]  实现 token 签发
  │    └─ Issue #112  [Task]  Checkpoint: 端到端登录跑通
  │
  ├─ Issue #102  [Feature]  billing    (blocked-by #101)
  └─ Issue #103  [Feature]  notifications (blocked-by #101)
```

| agent-skills 产物 | GitHub |
|---|---|
| 能力图 | Epic issue（type: Feature），正文放模块表 + 构建顺序 |
| `spec/<module>.md` | 模块 issue，**正文放摘要 + 文件链接**，不复制全文 |
| 构建顺序的依赖 | 模块 issue 之间的 `blocked-by` |
| `plan.md` | ⚠️ **不进 GitHub**，留在仓库 |
| 每个 task | sub-issue（type: Task） |
| checkpoint | sub-issue，标题以 `Checkpoint:` 开头 |
| task 完成 | **commit message** 里的 `Closes #<task-issue>` |
| 模块完成 | **一个 PR**，正文 `Closes #<module-issue>` |

**为什么 spec 正文不复制进 issue**：spec 会随讨论修改，复制一份必然分叉。

**为什么 plan 不进 issue**：见上游原话——设计决策、风险、开放问题无法干净地映射
到单个 issue。plan.md 的 Task List 章节退化成 issue 编号的有序索引。

### 三个问题，三个答案，不重叠

```
plan.md  回答「为什么这么拆」     → 留在仓库
issue    回答「有哪些活、谁在做」  → 进 GitHub
commit   回答「这个 task 干完了」  → 进 GitHub（Closes #<task-issue>）
PR       回答「这个模块交付了」    → 进 GitHub（Closes #<module-issue>）
```

常见误解是把「为什么」和「有哪些活」混成一层，或者把「有哪些活」和「干完了」
混成一层。

> **0.6.0 把 PR 从「这个活干完了」提到「这个模块交付了」。** 原先是一个 task 一个
> PR，结果一个需求被切成 N 个互不相干的合并事件：评审看不到完整交付面，做的人
> 每条都要停下来等合并。而「干完了」这件事 commit 本来就能回答 —— closing keyword
> 在 commit message 里同样生效（官方：*the issue will be closed when you merge the
> commit into the **default branch***）。
>
> 推论：**合并只能用 merge commit 或 rebase**。squash 把 N 条 message 压成一条，
> 「一个 task 一条 commit」这个回滚点当场消失。（注意理由不是「会漏关 issue」——
> GitHub 默认 `squash_merge_commit_message: COMMIT_MESSAGES` 会拼接 message，
> closing keyword 多半还在；但那是个可改的设置，不该拿它当保证。见 0.6.1。）

---

## 六、状态机

```
IDLE            没有任何 spec                        → /spec
IDLE(无活跃模块) 有 spec 但 activeModule 刻意为空       → 起新模块 / /spec
MAP_ONLY        有能力图但没有模块 spec          ⚠断链 → /spec 递归
SPECED          有 spec 但没有 issue 结构        ⚠断链 → /sync-map
TRACKED         有 issue 但没有 plan.md          ⚠断链 → /plan
PLANNED         全部就位                              → /next
TASK_CLAIMED    认领了 task，分支既不含 issue 号
                也不属于当前模块                ⚠断链 → 切分支
BUILDING(模块分支)   模块分支上有未提交改动           → /test → 提交带 Closes #<task>
TASK_READY(模块分支) 模块分支干净，还有 task 没落      → /build auto 继续
MODULE_READY    模块的 task 在本分支都有对应 commit    → /deliver 开模块 PR
BUILDING        （task 分支，老约定）有未提交改动      → /test → /deliver
TASK_READY      （task 分支，老约定）改动已提交        → /deliver
MODULE_DONE     模块无剩余 task                       → /next 推进模块
```

### 额外检测的三种违规

| 违规 | 为什么是问题 |
|---|---|
| 根目录有 `SPEC*.md` | `/build` 的路径规则只认 `spec/` 通配，找不到 |
| 存在 `todo.md`（tracker 模式下） | 和 issue 二选一，并存必然分叉 |
| 认领了 issue，分支**既不含 issue 号、也不是当前模块的分支** | 大概率在错误分支上工作 |

> ⚠️ **这一条 0.6.0 改过判据，改之前它是个假断链制造机。** 原判据只看「分支不含
> issue 号」—— 而模块级分支 `feat/<module-id>` 按定义就不含，约定一落地它每轮都在报。
> 现在要「两个都不满足」才报。模块分支的识别用**末段整段相等**而不是子串包含：
> 子串匹配下 module id 叫 `a` 时分支 `master` 会被认成模块分支（已有反向用例钉住）。
>
> 这是本项目「假断链比不报断链危害大得多」那条不变量的又一个实例 ——
> **改约定必须同改状态机，否则新约定的正常状态就是旧状态机眼里的违规。**

---

## 七、非目标

明确不做的事：

- **不 fork agent-skills** —— 上游更新就断了
- **不把 plan.md 搬进 issue** —— 上游明确说了不该这么做
- **不做 todo.md 和 issue 的双向同步** —— 二选一，双保险必然分叉
- **不用 label 模拟 issue type** —— 无层级、无依赖，筛选逻辑全废
- **不在断链时自动补齐** —— 断链可能是用户故意的
- **不覆盖用户的 CLAUDE.md / settings.json** —— 追加和合并

---

## 八、已知限制

1. **任务层自动化只覆盖 `github` 和 `none`**。GitLab / Jira 需要写各自的
   取任务命令等价实现。当前只检测到 plan 层。
   > 0.7.7 之前这条限制的**表现**是错的：声明 `gitlab` / `jira` 的项目会落进
   > 「gh 不可用，恢复 gh 后 /next」的降级分支（`gh` 不是不可用，是无关），
   > 缺条目号时还会被建议 `/sync-map` —— 而那个命令会去 `gh` 建 GitHub issue。
   > 「不支持」和「给错指引」是两回事：**前者是限制，后者是 bug。**
2. **需要 `gh` ≥ 2.94.0** —— 低于此版本没有 `--type` / `--parent` / `--blocked-by`。
3. **能力图的文件名是本项目约定的**（`spec/CAPABILITY-MAP.md`）。上游只说
   *Save the approved map at the project root*，没给具体文件名——这是上游的一处
   自相矛盾：它同时声称「是这张图、而不是猜文件名，构成了『存在哪些东西』的索引」，
   却没规定索引本身的位置。
4. **多人协作的任务认领依赖 assignee**，没有加锁机制，理论上存在竞态。
5. ~~`--no-claude-md` 模式下感知晚一步，靠 hook 每轮兜底~~ —— **0.7.5 更正。**
   实测发现兜不住：hook 注入的是**状态**，而让 skill 被加载的是那句**指令**。
   B 组（= 这个模式）全程没加载 skill。0.7.5 起 hook 在零足迹模式下把触发指令
   补进注入内容，代价只由零足迹项目承担。
   > 教训：**「另一个机制会兜住」是最容易想当然的一类论断**，因为它听起来像
   > 系统设计而不像假设。这条从 0.7.0 起写在已知限制里，写的时候没验，
   > 一验就是反的。
6. **`MODULE_READY` 的判定只认 `main` / `master` 作为基线分支。** 默认分支叫别的
   （`trunk`、`develop`）时它恒不触发，表现是一直建议「继续取任务」。
   这是**保守失败**（不会误报断链），但要人自己判断什么时候开 PR。

---

## 九、参考

- 上游仓库：`https://github.com/addyosmani/agent-skills`
- **核对基准：commit `5a5ea45`（2026-08-21）**，也是本插件的最低上游版本要求。
  更早的版本没有 Phase 0 和 Task List Target，本文的缺口 A/B/C/D/E 全部悬空 ——
  详见 [upstream-analysis.md](upstream-analysis.md) 顶部。
- 关键源文件：
  - `skills/spec-driven-development/SKILL.md` Phase 0（多模块）
  - `skills/planning-and-task-breakdown/SKILL.md` Output Files（tracker 扩展点）
  - `commands/build.toml` 第 30-31 行（spec 查找规则）
  - `docs/agents.md` 第 22、55 行（编排责任归属）
