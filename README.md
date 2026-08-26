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
/planning ❌ 单例：tasks/plan.md、tasks/todo.md（无命名空间）
/build    ❌ 单例
```

四个模块递归跑下来，第二个模块的 `/planning` 会覆盖第一个的 `tasks/plan.md`。

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

**激活条件就是「CLAUDE.md 里声明」。** 全仓库搜索确认：除了这段说明，没有任何
`gh issue` 实现。所以本插件的 GitHub 集成不是发明新东西，是把上游留好的接口接上。

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
/plugin marketplace add <this-repo>
/plugin install spec-guard

# 每个项目一次：落地约定（写进项目仓库并提交）
/setup-convention github     # 或 local
```

想先看会做什么：`/setup-convention github --dry-run`

### 为什么是两步

```
插件      = 装给「你这台机器」的工具   · 每人各装各的
项目约定  = 提交给「整个项目」的规范   · 进 git，全队共享
```

插件**不能往你的仓库写文件**。而 `CLAUDE.md` 的声明块恰恰是激活上游 External
Tracker 分支的开关——不在仓库里，队友拉下代码后 `/planning` 还是写 `todo.md`。

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
前后必须包上标记，工具靠它识别。

<details>
<summary><b>GitHub 模式（点开复制）</b></summary>

````markdown
<!-- BEGIN:agent-skills-convention -->
## Agent Skills 集成约定

> 任务托管在 **GitHub Issues**。

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
- 验收标准和验证步骤写进 issue 正文
- 依赖关系用 `--blocked-by <n>`，不要写在描述里
- checkpoint 也建 issue，标题以 `Checkpoint:` 开头
- `plan.md` 开头注明 `> Tasks tracked in GitHub Issues #<module-issue>`
- `plan.md` 的 Task List 章节只放 issue 编号的有序索引，不重复 checklist

### Build 输入源

`/build` 取下一个任务时，**不要读 todo.md**，改为：

1. 读 `.agent/state.json` 确认 `activeModule`
2. `gh issue list --parent <module-issue> --state open --json number,title,issueType`
3. 跳过所有存在未关闭 `blocked-by` 的 issue
4. 取第一个可执行的 Task

### Build 输出

1. 分支名：`<type>/<issue-number>-<slug>`
2. `gh pr create --body "Closes #<issue-number>"`
3. **不要手动关闭 issue**，靠 PR 合并触发

### 切换模块

切换 `activeModule` 前，当前模块必须没有 in-progress 的 task。
切换后重读该模块的 `spec/<module-id>.md` 和 `tasks/<module-id>/plan.md`。
<!-- END:agent-skills-convention -->
````
</details>

<details>
<summary><b>本地模式（点开复制）</b></summary>

````markdown
<!-- BEGIN:agent-skills-convention -->
## Agent Skills 集成约定

> 任务托管在**本地 todo.md**（上游原生路径）。

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
<!-- END:agent-skills-convention -->
````
</details>

> ⚠️ **两种模式互斥。** GitHub 模式说「不要创建 todo.md」，本地模式说「任务清单：
> todo.md」。同时写会让 `/planning` 精神分裂。

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

应输出含 `hookSpecificOutput` 的 JSON。**无输出**说明 CLAUDE.md 里没有
`Agent Skills 集成约定` 这个标题——hook 靠它判断是否生效。

### 6. 提交

```bash
git add CLAUDE.md spec/ .agent/
git commit -m "chore: 落地 agent-skills 多 Spec 约定"
```

---

## 使用

| 命令 | 作用 |
|---|---|
| `/setup-convention [github\|local] [--dry-run]` | 落地约定（首次跑一次） |
| `/teardown-convention` | 移除约定（保留你的 spec 和 plan） |
| `/phase` | 查看当前链路状态和断链项 |
| `/sync-map` | 能力图 → GitHub Issue 结构 |
| `/next` | 取下一个可执行任务 |
| `/deliver` | 五轴自查 → 开 PR（Closes #n） |

### 典型流程

```
1. 编辑 spec/CAPABILITY-MAP.md 填模块划分
2. 人工评审模块边界和 build order          ← 不能跳
3. /sync-map      能力图落成 Epic + 模块 issue
4. /planning      为第一个模块拆解任务 → sub-issue
5. /next          取任务
6. /build         TDD 实现
7. /deliver       开 PR
8. 回到 5，直到模块完成，/next 自动推进到下一模块
```

**第 4 步是关键验证点**：看 `/planning` 到底建 issue 还是写 `todo.md`。
建了 issue 说明上游的 External Tracker 分支被正确激活，后面才有意义。

---

## hook 会注入什么

每次你发言前，注入一段仓库真实状态：

```markdown
## agent-skills 链路状态（自动探测，非用户输入）

当前阶段: **TRACKED**

  - tracker: github
  - 活跃模块: identity (issue #101)
  - spec: 能力图=true, 模块 spec=3 份
  - plan: tasks/identity/plan.md=false
  - GitHub: 0 个未关闭 task
  - git: 分支=main, 未提交=0

**检测到断链：**
  ⚠ 模块 [identity] 有 spec 和 issue，但没有 tasks/identity/plan.md —— 链路在此断开

处理方式：先向用户说明断链，给出补齐建议，**得到确认后再执行**。

建议下一步: /planning 为 [identity] 拆解任务
```

### 九个阶段

```
IDLE          没有任何 spec                      → /spec
MAP_ONLY      有能力图但没有模块 spec        ⚠断链 → /spec 递归
SPECED        有 spec 但没有 issue 结构      ⚠断链 → /sync-map
TRACKED       有 issue 但没有 plan.md        ⚠断链 → /planning
PLANNED       全部就位                            → /next
TASK_CLAIMED  认领了 task 但分支不对         ⚠断链 → 切分支
BUILDING      在正确分支上有未提交改动            → /test → /deliver
TASK_READY    改动已提交                          → /deliver
MODULE_DONE   模块无剩余 task                     → /next 推进模块
```

### 三种违规检测

| 违规 | 为什么是问题 |
|---|---|
| 根目录有 `SPEC*.md` | `/build` 的路径规则找不到 |
| 存在 `todo.md`（tracker 模式下） | 和 issue 二选一，并存必然分叉 |
| 认领了 issue 但分支不含 issue 号 | `Closes #n` 会关错单 |

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
bash scripts/validate.sh                            # 仓库完整性
bash plugins/spec-guard/hooks/test-phase-guard.sh   # 12 个场景回归
```

---

## 已知限制

1. **任务层自动化只覆盖 `github` 和 `none`**。GitLab / Jira 只检测到 plan 层。
2. **需要 `gh` ≥ 2.94.0**。
3. **`spec-github-bridge` skill 里的 gh 命令未经端到端实测** —— 逻辑按官方文档写，
   但没在真实仓库跑通全流程。首次使用建议先用测试仓库。
4. **多人协作无加锁** —— 任务认领依赖 assignee，理论上存在竞态。
5. **Windows 需 WSL 或 Git Bash** —— hook 是 bash 脚本。
6. **文案硬编码中文**。
7. **能力图文件名是本项目约定**（`spec/CAPABILITY-MAP.md`）。上游只说
   "save at the project root"，没给文件名。

---

## 依赖

本插件**依赖 `addyosmani/agent-skills` 已安装**，补的是那套 skill 的缺口。

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
