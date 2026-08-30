# spec-guard

给 [`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills) 补三样东西的 Claude Code 插件：
**多模块 Spec 支持**、**GitHub Issue 打通**、**链路断裂检测**。

> **给 AI agent 的提示**：本 README 包含完整的手动安装步骤和需要写入 `CLAUDE.md`
> 的原文。你可以直接照做，不必依赖 `/setup-convention` 命令。见
> [手动安装](#手动安装给-agent-或不想跑命令的人)。

---

## 文档

| | |
|---|---|
| [docs/design.md](docs/design.md) | 需求与设计：五个缺口、核心决策、对象模型、状态机、已知限制 |
| [docs/walkthrough.md](docs/walkthrough.md) | 端到端实跑记录：真实产物、真实输出，以及跑出来的那个 bug |
| [docs/upstream-analysis.md](docs/upstream-analysis.md) | 上游源码分析：每条结论对应的源码行号 + 重新核对清单 |
| [CLAUDE.md](CLAUDE.md) | 开发本插件的 agent 配置 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 贡献指南 |
| [CHANGELOG.md](CHANGELOG.md) | 版本记录 |

---

## 为什么需要它

`agent-skills` 是一套优秀的工程流程 skill，但在三个场景下会失效。每条都对应上游
源码的具体位置（详见 [docs/upstream-analysis.md](docs/upstream-analysis.md)）。

### ① 多需求并行时产物互相覆盖

`spec-driven-development` 的 Phase 0 支持多模块，会生成能力图和
`SPEC-identity.md`、`SPEC-billing.md`。**但下游没跟上**：

```
/spec     ✅ 多模块
/plan ❌ 单例：tasks/plan.md、tasks/todo.md（无命名空间）
/build    ❌ 单例
```

四个模块递归跑下来，第二个模块的 `/plan` 会覆盖第一个的 `tasks/plan.md`。

### ② spec 放根目录时 `/build` 找不到

`commands/build.toml:30` 的规则：只在**仓库根 `SPEC.md`**、**`docs/SPEC.md`**、
**`spec/` 下的文件**三处找。

**只有第三条是通配的。** Phase 0 生成的 `SPEC-identity.md` 放在根目录，恰好落在
匹配范围外——这是上游内部的一处不一致。

### ③ 链路走一半断了

`docs/agents.md:22,55`：

> **The user (or a slash command) is the orchestrator.**
> Sequential slash commands **run by the user**（/spec → /plan → /build → /test → /review）

**顺序编排的责任被显式交给了人。** 没有任何机制推进状态机。所以「产生了 spec 但
没建 task」不是 bug，是设计使然。

### 上游其实留好了接口

`planning-and-task-breakdown/SKILL.md:155` 有个 **Task List Target** 章节：

> **External tracker:** if the project's agent rules (`CLAUDE.md`, `AGENTS.md`, etc.)
> or the user designate an issue tracker (e.g. GitHub Issues, Jira, Linear), create one
> tracker item per task **instead of** writing `tasks/todo.md`.

**上游的激活条件就是「CLAUDE.md 里声明」。** 全仓库搜索确认：除了这段说明，没有任何
`gh issue` 实现。所以本插件的 GitHub 集成不是发明新东西，是把上游留好的接口接上。

（本插件自己的 hook 从 0.7.0 起认两个信号：CLAUDE.md 的约定标题，**或** `.agent/state.json`
存在。后者是给不想动 CLAUDE.md 的项目用的，见 `--no-claude-md`。上游那半仍然只认前者。）

---

## 核心设计：状态注入，不是意图分类

「说了需求但没触发对应 skill」的直觉解法是加一层路由 skill。**这行不通**——
路由 skill 自己也要靠 description 触发，是同一个问题。

改为注入**确定性事实**：文件在不在、issue 有没有、分支干不干净。模型看得见缺什么，
路由自然就准，断链在下一轮对话开头就暴露。

| | 路由 skill | 状态注入 hook |
|---|---|---|
| 触发可靠性 | 靠 description 匹配 —— 同样的问题 | 100%，hook 强制执行 |
| 断链检测 | 只在被调用时 | 每次发言 |
| 上下文成本 | 整个 skill 常驻 | ~200 token |
| 出错影响 | 跑错流程 | 最坏多说一段状态 |

---

## 安装

### 前置

| | 要求 |
|---|---|
| `python3` | 必需（hook 的 JSON 解析） |
| `git` | 必需 |
| `bash` | 必需（Windows 需 WSL 或 Git Bash） |
| `gh` | **≥ 2.94.0**，仅 github 模式 |
| `agent-skills` | 本插件是它的补充，不是替代品 |

⚠️ **光看 `gh --version` 不够**。PATH 里可能有多个 `gh`，版本号来自新的、实际执行
的是旧的。安装脚本会额外验证 `gh issue create --help | grep -- "--parent"`。

### 两步

```
# 一次性：装插件（工具装到你这台机器）
/plugin marketplace add yizhongkaimail-collab/spec-guard-plugin
/plugin install spec-guard

# 每个项目一次：落地约定（写进项目仓库并提交）
/setup-convention github     # 或 local
```

想先看会做什么：`/setup-convention github --dry-run`

**新项目请把这一步放在 `/spec` 之前。** 没落约定的项目上 spec-guard 是静默的
（见下面「默认不生效」），`/spec` 会走 agent-skills 的默认落点，把
`SPEC-<模块>.md` 和能力图散在项目根上 —— 那正是问题①要治的形状，而且过程中
不会有任何提示。已经散了的项目用 `/setup-convention github --migrate` 迁回来
（先加 `--dry-run` 看会动哪些文件）。

### 为什么是两步

```
插件      = 装给「你这台机器」的工具   · 每人各装各的
项目约定  = 提交给「整个项目」的规范   · 进 git，全队共享
```

插件**不能往你的仓库写文件**。而 `CLAUDE.md` 的声明块恰恰是激活上游 External
Tracker 分支的开关——不在仓库里，队友拉下代码后 `/plan` 还是写 `todo.md`。

---

## 手动安装（给 agent，或不想跑命令的人）

`/setup-convention` 内部调用的是
[`hooks/setup-convention.sh`](plugins/spec-guard/hooks/setup-convention.sh)。
下面是它做的全部事情。

### 1. 建目录

```bash
mkdir -p spec tasks .agent
```

### 2. 往 `CLAUDE.md` **追加**下面这段

⚠️ **追加，不是覆盖。** 用户的 CLAUDE.md 里有他们自己的项目规范。
前后必须包上标记，工具靠它识别 —— `/setup-convention --replace` 升级本块时
也只认这对标记。

> 下面两段与 [`templates/claude-block-*.md`](plugins/spec-guard/templates/) **逐字节一致**，
> 由 `scripts/check-readme-sync.py` 在 `validate.sh` 里钉住。改了模板忘了改这里会直接报错 ——
> 这个 README 曾经内嵌一份 106 行的旧版，**分叉了三个版本没人发现**。

<details>
<summary><b>GitHub 模式（点开复制）</b></summary>

<!-- SYNC:claude-block-github BEGIN -->
````markdown
<!-- BEGIN:agent-skills-convention -->
## Agent Skills 集成约定

> 由 `/setup-convention github` 生成。**这里只留推导不出来的事实，「怎么做」在 `spec-github-bridge` skill 里。**
> 保留 `<!-- BEGIN/END -->` 标记（HTML 注释不进 context，是免费的），`/setup-convention --replace` 靠它升级本块。

- 任务的事实源是 **GitHub Issues**。**不要创建任何 `todo.md`**
- 能力图 `spec/CAPABILITY-MAP.md`，模块 spec `spec/<module-id>.md`（kebab-case，一次选定中途不改名）
- **不要**在项目根建 `SPEC.md` / `SPEC-<module>.md` —— `/build` 只认根 `SPEC.md`、
  `docs/SPEC.md`、`spec/` 三条路径，**只有第三条是通配的**
- 计划文档 `tasks/<module-id>/plan.md`；活跃模块与 issue 号在 `.agent/state.json`
- 分支是 `<type>/<module-id>`，**一个模块一条**，不是一个 task 一条

**动 spec、拆任务、取任务、交付之前，先加载 `spec-github-bridge` skill。**
上面五条是「放哪里」，skill 才有「怎么做」：issue 落库、`--parent` / `--blocked-by`、
归档标记、`/build auto` 连贯推进、模块级 PR 与合并策略。跳过它必然写出双真相源。
<!-- END:agent-skills-convention -->
````
<!-- SYNC:claude-block-github END -->

</details>

<details>
<summary><b>本地模式（点开复制）</b></summary>

<!-- SYNC:claude-block-local BEGIN -->
````markdown
<!-- BEGIN:agent-skills-convention -->
## Agent Skills 集成约定

> 由 `/setup-convention local` 生成。任务托管在**本地 todo.md**（Addy 原生路径）。
> 保留 `<!-- BEGIN/END -->` 标记，`/setup-convention --replace` 靠它升级本块。

- 能力图 `spec/CAPABILITY-MAP.md`，模块 spec `spec/<module-id>.md`（kebab-case，一次选定中途不改名）
- **不要**在项目根建 `SPEC.md` / `SPEC-<module>.md` —— `/build` 只认根 `SPEC.md`、
  `docs/SPEC.md`、`spec/` 三条路径，**只有第三条是通配的**
- 每个模块的产物互相隔离：`tasks/<module-id>/plan.md` + `tasks/<module-id>/todo.md`，
  **不要共用 `tasks/plan.md`**
- `/build` 取任务：读 `.agent/state.json` 的 `activeModule`，从该模块的 `todo.md`
  取第一个未勾选项，**不跨模块取**
- 切换 `activeModule` 前当前模块不能有进行中的 task；切换后重读该模块的 spec 和 plan
<!-- END:agent-skills-convention -->
````
<!-- SYNC:claude-block-local END -->

</details>

**两种模式二选一，不要都写。** github 模式的任务在 issue 里，本地模式在
`tasks/<module>/todo.md`。同时写会让 `/plan` 精神分裂。

**「怎么做」不在这段里** —— 它在 `spec-github-bridge` skill 里，按需加载。
声明块只放推导不出来的事实（路径 / tracker 类型 / 几条硬禁令）+ 一句触发指令。
这是官方对 CLAUDE.md 的明确建议（多步过程应移进 skill 或 path-scoped rule），
也是 0.7.0 把它从 106 行砍到 15 行的原因：官方建议 target under 200 lines，
而它曾经一口气占掉使用者 CLAUDE.md 的 34%。

### 3. 建 `.agent/state.json`

```json
{
  "tracker": "github",
  "initiative": { "title": "", "issue": null, "map": "spec/CAPABILITY-MAP.md" },
  "modules": {},
  "activeModule": "",
  "updatedAt": ""
}
```

本地模式把 `tracker` 改成 `"none"`。**这个文件要提交进仓库**——它是跨会话、
跨成员的进度锚点。

### 4. 建 `spec/CAPABILITY-MAP.md`

复制 [templates/CAPABILITY-MAP.md](plugins/spec-guard/templates/CAPABILITY-MAP.md)。

### 5. 验证

```bash
CLAUDE_PROJECT_DIR=$(pwd) bash <plugin-root>/hooks/phase-guard.sh
```

应输出含 `hookSpecificOutput` 的 JSON。**无输出**说明两个激活信号都不满足：
CLAUDE.md 里没有 `Agent Skills 集成约定` 这个标题，且没有 `.agent/state.json`。

### 6. 提交

```bash
git add CLAUDE.md spec/ .agent/
git commit -m "chore: 落地 agent-skills 多 Spec 约定"
```

---

## 装了之后，上游的哪些默认行为变了

**本插件不提供 agent-skills 的使用教程，也不该提供** —— 上游自己有 README、
`docs/` 和 24 份 SKILL.md，而且它会变（Phase 0 和 Task List Target 就是
2026-08 才加的）。写一份平行教程等于开第二个真相源，必然分叉。

上游永远不会替你写的只有这一张表 —— **spec-guard 改了它哪些默认行为**：

| | 上游默认 | 装了 spec-guard |
|---|---|---|
| 单模块 spec | `SPEC.md`（项目根） | `spec/<module-id>.md` |
| 多模块 spec | `SPEC-<module>.md`（项目根） | `spec/<module-id>.md` |
| 能力图 | 项目根，**文件名未定义** | `spec/CAPABILITY-MAP.md` |
| 计划文档 | `tasks/plan.md`（单例，多模块会互相覆盖） | `tasks/<module-id>/plan.md` |
| 任务清单 | `tasks/todo.md` | github 模式下**不存在**，改为 issue |
| 谁推进流程 | 用户自己按顺序敲命令 | hook 每轮注入状态 + 报断链 |
| 产物对不对 | 无检测 | `/verify-artifacts` |
| 交付粒度 | 未定义（`/build` 到 commit 为止） | 一个模块一条分支一个 PR，禁 squash |

其余一切照旧 —— `/spec` `/plan` `/build` `/test` `/review` 的用法、
各 skill 的触发条件、persona 的行为，全部走上游文档。

> ⚠️ **`/spec` 的 Phase 0 默认不触发。** 上游原话：*Phase 0 exists for the
> exception, not the rule* —— 它明确指示模型「大多数需求是单能力，直接跳过」。
> 想让它触发，最可靠的是在需求里直接点名「先给我能力图，评审通过后再逐个写
> spec」，而不是指望模型自己判断。

## 使用

| 命令 | 作用 |
|---|---|
| `/setup-convention [github\|local] [--dry-run]` | 落地约定（首次跑一次） |
| `/setup-convention … --replace` | 已装的声明块就地升级到当前模板（只动标记内） |
| `/setup-convention … --no-claude-md` | 不写声明块，hook 改由 `.agent/state.json` 激活（**仅 github 模式**） |
| `/setup-convention … --migrate` | 把根上的 `SPEC-<模块>.md` / 能力图迁进 `spec/`（不加只报告，不动文件） |
| `/teardown-convention` | 移除约定（保留你的 spec 和 plan） |
| `/phase` | 查看当前链路状态和断链项 |
| `/verify-artifacts` | 校验已落地的产物是否符合约定 |
| `/sync-map` | 能力图 → GitHub Issue 结构 |
| `/next` | 取下一个可执行任务 |
| `/deliver` | 五轴自查 → 开**模块级** PR（Closes #module-issue） |

### 典型流程

```
1. 编辑 spec/CAPABILITY-MAP.md 填模块划分
2. 人工评审模块边界和 build order          ← 不能跳
3. /sync-map      能力图落成 Epic + 模块 issue
4. /spec          为第一个模块写 spec/<module-id>.md     ← 每个模块一次
5. /plan          为该模块拆解任务 → sub-issue
6. git checkout -b <type>/<module-id>       ← 一个模块一条分支
7. /build auto    跑完整个模块（每个 task 一条带 Closes #n 的 commit）
8. /deliver       开模块级 PR（Closes #module-issue）
9. 合并用 --merge 或 --rebase，**不要 squash**
   然后 /next 推进到下一模块 —— 回到第 4 步，不是回到第 1 步
```

**第 4 步以前漏写了。** 少了它，照着 README 一路做到第 3 步会得到一个
`MAP_ONLY` 断链（「能力图已存在但一份模块 spec 都没有」）—— 文档把用户
送进了自己的检查器要报警的状态。

**3 和 4 可以互换。** `/sync-map` 只依赖能力图，不依赖任何模块 spec
（0.7.19 起明确写进 skill）；先写第一个模块的 spec 再落库也行。

**第 5 步是关键验证点**：看 `/plan` 到底建 issue 还是写 `todo.md`。
建了 issue 说明上游的 External Tracker 分支被正确激活，后面才有意义。

---

## hook 会注入什么

每次你发言前，注入一段仓库真实状态（下面这段是 v0.7.17 上真实跑出来的，
版本行会随你装的版本变）：

```markdown
## agent-skills 链路状态（自动探测，非用户输入）

当前阶段: **TRACKED**

  - 活跃模块: identity (issue #101)
  - tracker: github
  - spec: 能力图=true, 模块 spec=3 份
  - plan: tasks/identity/plan.md=false
  - git: 分支=main, 未提交=0
  - spec-guard: v0.7.17

**检测到断链：**
  ⚠ 模块 [identity] 有 spec 和 issue，但没有 tasks/identity/plan.md —— 链路在此断开

处理方式：先向用户说明断链，给出补齐建议，**得到确认后再执行**。不要自作主张跳过或补齐。

建议下一步: /plan 为 [identity] 拆解任务

以上是仓库客观状态。若用户意图与之冲突，以用户为准，但要先指出冲突。
```

### 阶段

下面是**基名**。实际输出会带模式后缀（`(本地模式)` / `(gitlab)` /
`(模块分支)` / `(gh 不可用，降级判定)`），组合起来共 28 种取值。

```
IDLE              没有任何 spec；或有 spec 但刻意没有活跃模块  → /spec
MAP_ONLY          有能力图但没有模块 spec                ⚠断链 → /spec 递归
SPECED            有 spec 但没有 issue 结构              ⚠断链 → /sync-map
TRACKED           有 issue 但没有 plan.md                ⚠断链 → /plan
PLANNED           全部就位                                    → /next
PLANNED (任务未落库) plan.md 有任务，但模块 issue 下一个
                  sub-issue 都没有                       ⚠断链 → skill 操作二
TASK_CLAIMED      认领了 task，却既不在模块分支
                  也不在带 issue 号的分支                ⚠断链 → 切模块分支
MODULE_BRANCH     在模块分支上（gh 不可用时的降级判定）        → 恢复 gh 后 /next
BUILDING          有未提交改动                                → /test → 提交
TASK_READY        改动已提交，模块还有剩余 task                → /build auto 或 /next
MODULE_READY      模块内 task 都有对应 commit                 → /deliver 开模块 PR
READY (本地模式)   本地模式下 todo.md 就绪                     → /build
MODULE_DONE       模块的 sub-issue 建过、且全部关闭            → /next 推进模块
```

> `MODULE_DONE` 要求 sub-issue **建过**。「一条都没建过」判的是
> `PLANNED (任务未落库)` —— 两者的「未关闭数」都是 0，但含义相反（见 0.7.15）。

### 三种违规检测

| 违规 | 为什么是问题 |
|---|---|
| 根目录有 `SPEC*.md` | `/build` 的路径规则找不到 |
| 存在 `todo.md`（tracker 模式下） | 和 issue 二选一，并存必然分叉。**前 10 行含 `已归档`/`ARCHIVED` 的不计** —— 那是历史记录不是活清单 |
| 认领了 task，却既不在模块分支 `<type>/<module-id>`、也不在带 issue 号的分支上 | 大概率在错误分支上工作。**0.6.0 起交付粒度是模块**，所以「分支不含 issue 号」本身是正常的，不再是违规 |

---

## 三个安全设计

**① 默认不生效** —— hook 检查目标项目的 CLAUDE.md 是否含约定标题，没有就静默
`exit 0`。装了插件不会污染你其他项目。

**② 探测失败就降级，不误报**

| 情况 | 行为 |
|---|---|
| `gh` 没装/没登录/离线 | 退化本地判定，标注 `(gh 不可用，降级判定)` |
| 远端是 GitLab/Gitee | `tracker: other`，**只检查 spec/plan 层，不碰任务层** |
| 无 remote | 自动本地模式 |

早期版本在 GitLab 项目上会永远误报「没建 issue」。**假断链比不报断链危害大得多**
——它会让人几天内就关掉整个机制。

**③ 不越权** —— 断链处理规则写死成「先说明、得到确认后再执行」。断链可能是
用户故意的。

---

## 三种 tracker 模式

判定顺序：`state.json` 的 `tracker` 字段 → git remote 域名推断 → `none`

| 模式 | 任务清单在哪 | 检测范围 |
|---|---|---|
| `github` | GitHub Issues | 完整（含任务层） |
| `github` + `issueTypes:false` | GitHub Issues（个人仓库） | 完整，仅省略 `--type` |
| `none` | `tasks/<module>/todo.md` | 完整（上游原生路径） |
| `other` / `gitlab` / `jira` | 你自己的系统 | **只到 plan 层** |

**目录约定三种模式完全一样**，只有任务层落点不同。从 `none` 迁到 `github`，
`spec/` 和 `plan.md` 一个字不用改。

> 不确定的话**先用 `local` 跑两周**，验证多模块拆分本身跑不跑得通。

---

## 性能

| 场景 | 耗时 |
|---|---|
| 未启用约定的仓库（最常见） | ~3 ms |
| 已启用，无 `gh` 调用 | ~154 ms |
| 已启用 + `gh issue list` | **未实测，含网络往返** |

⚠️ 最后一行是已知风险。如果发现卡顿，临时把 `state.json` 的 `tracker` 改成 `none`
可绕过。

---

## 测试

```bash
/bin/bash scripts/validate.sh                              # 仓库完整性
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
```

> ⚠️ **macOS 上显式用 `/bin/bash`（那是 3.2）。** 装了 Homebrew 的话 `bash` 会指向
> 5.x —— 那就绕过了本机唯一能暴露 bash 3.2 兼容问题的环境，而 CI 的 macOS matrix
> 需要账户级 Actions 可用才会跑。


---

## 已知限制

1. **任务层自动化只覆盖 `github` 和 `none`**。GitLab / Jira 只检测到 plan 层 ——
   0.7.7 起它们有自己的状态分支（`PLANNED (gitlab)` 等），不再被塞 GitHub 专属建议。
2. **需要 `gh` ≥ 2.94.0**。
3. ~~`/deliver` 的 PR 环节未经端到端实测~~ —— **0.7.1 起作废，已实测。**
   在 `sentinel-livelab` 上真跑了 4 个 PR（#65 #67 #70 #72），`gh pr create` →
   正文 / commit message 里的 `Closes #n` → 合入默认分支自动关 issue → 分支清理，
   全链路验证通过。最干净的一条证据：PR #70 合并于 `13:20:34Z`，
   issue #69 关闭于 `13:20:35Z`（`reason=COMPLETED`）。
   详见 [docs/walkthrough.md 第三次实跑](docs/walkthrough.md)。
   > 这条免责声明在 0.6.0–0.7.0 期间已经不成立却还挂着 —— **一条过期的免责声明
   > 比过期文档更糟，它在劝退使用者用一个已经证明可用的功能。**
4. **多人协作无加锁** —— 任务认领依赖 assignee，理论上存在竞态。
5. **个人仓库没有 issue types，会自动降级** —— `--type Feature/Task` 依赖 GitHub
   issue types，这是**组织级功能**。`/setup-convention github` 会探测并把结果写进
   `.agent/state.json` 的 `issueTypes`，下游据此省略 `--type`。**层级（`--parent`）和
   依赖（`--blocked-by`）在个人免费仓库上实测可用**，所以流程一步不少，
   只是失去按 type 跨仓筛选的能力。
6. **Windows 需 WSL 或 Git Bash** —— hook 是 bash 脚本。
7. **文案硬编码中文**。
8. **插件假设「从零开始 + 永远在做某件事」** —— 对已有自己一套约定的项目，
   `/setup-convention` 的声明块是**替换**而非适配：追加之后 `CLAUDE.md` 里会出现
   两个互相矛盾的真源，比覆盖更糟。落地前请人工核对现有约定，必要时**只保留
   激活标题 `## Agent Skills 集成约定`**，块内容改写成指向自有约定的映射表。
   见 [docs/walkthrough.md 第二次实跑](docs/walkthrough.md)。
9. **能力图文件名是本项目约定**（`spec/CAPABILITY-MAP.md`）。上游只说
   "save at the project root"，没给文件名。
10. **`--replace` 只认完整标记行** `<!-- BEGIN:agent-skills-convention -->`。
    手工改坏标记（比如删掉 `<!-- -->`）的项目会被当成「没装过」而追加第二块。
11. **`--no-claude-md` 零足迹模式：0.7.5 起才真正可用。**
    0.7.0–0.7.4 期间这个模式是**残的** —— 实测（`evals/skill-deferral.sh` 的 B 组
    就是它）：hook 正常激活、状态照常注入，但模型**全程没加载 skill**，
    转头按自己的想法设计表结构去了。当时文档写的「靠 hook 每轮兜底」是想当然：
    hook 注入的是**状态**，而让 skill 被加载的是那句**指令**。
    0.7.5 起 hook 在这个模式下会把触发指令补进注入内容（只有零足迹项目付这个
    代价，写了声明块的项目一个字都不多）。

---

## 依赖

本插件**依赖 `addyosmani/agent-skills` 已安装**，补的是那套 skill 的缺口。

⚠️ **最低上游版本：commit `5a5ea45`（2026-08-21）或更新。** 本插件依赖的两处上游结构
（`spec-driven-development` 的 Phase 0、`planning-and-task-breakdown` 的 Task List Target）
在更早的版本里**根本不存在**。装了旧版的症状是「Phase 0 永远不触发、插件好像没用」。核对：

```bash
M=~/.claude/plugins/marketplaces/addy-agent-skills
git -C "$M" log -1 --format='%h %ad' --date=short   # 应 >= 5a5ea45 / 2026-08-21
grep -c "Task List Target" "$M/skills/planning-and-task-breakdown/SKILL.md"   # 应为 1
```

旧版升级：`/plugin update agent-skills@addy-agent-skills` 然后 `/reload-plugins`。

```
/plugin marketplace add addyosmani/agent-skills
/plugin install agent-skills@addy-agent-skills
/plugin install spec-guard
```

两者 hook 并存不冲突（一个 SessionStart，一个 UserPromptSubmit）。

> ⚠️ 上游更新后，按 [docs/upstream-analysis.md](docs/upstream-analysis.md) 末尾的
> **重新核对清单**验证本插件是否仍然成立。有些缺口上游补上了，对应功能就该撤掉。

---

## License

MIT
