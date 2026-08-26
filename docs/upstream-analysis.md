# 上游源码分析：addyosmani/agent-skills

本文记录 spec-guard 各项设计决策的**源码依据**。

| | |
|---|---|
| 末次核对 | **2026-08-26** |
| 上游 commit | **`5a5ea45`**（2026-08-21） |
| 扫描范围 | 187 个文件全量 |

> **最低上游版本：commit `5a5ea45`（2026-08-21）或更新。**
> 本插件依赖的两处上游结构 —— `spec-driven-development` 的 **Phase 0** 和
> `planning-and-task-breakdown` 的 **Task List Target** —— 在更早的版本里**根本不存在**
> （实测 `7829ffd` / 2026-07-26 那版：175 个文件，两者全树 0 命中，
> `commands/spec.toml` 无条件写 `Save the spec as SPEC.md in the project root`）。
>
> 装了旧版会表现为：Phase 0 永远不触发，`CLAUDE.md` 声明块也不是「激活上游已有分支」
> 而是凭空覆盖上游默认行为。**排查「插件好像没用」时先核对 commit，不要只看功能。**
>
> 目的：避免「为什么这么设计」的知识只活在某次对话里。上游更新后重新核对时，
> 对着这份文档逐条验证即可。

---

## 一、仓库结构

```
AGENTS.md  CLAUDE.md  CONTRIBUTING.md  README.md  plugin.json
agents/    commands/  docs/  evals/  hooks/  references/  scripts/  skills/
```

- **skills/** —— 24 个（23 个生命周期 skill + `using-agent-skills` 元技能）
- **commands/** —— 8 个 toml：`spec` `planning` `build` `test` `review` `ship`
  `code-simplify` `webperf`
- **hooks/** —— 只有一个 `SessionStart`，作用是注入 `using-agent-skills` 元技能
- **agents/** —— 4 个 persona：`code-reviewer` `test-engineer` `security-auditor`
  `web-performance-auditor`

---

## 二、产物文件

全仓库扫描 skills/ commands/ docs/ 中出现的产物路径，按频次：

```
7  tasks/todo.md
5  tasks/plan.md
2  SPEC.md
1  SPEC-identity.md
1  SPEC-billing.md
1  PERF.md
```

| 文件 | 由谁生成 | 默认位置 |
|---|---|---|
| `SPEC.md` | `/spec` | 项目根 |
| `SPEC-<module>.md` | `/spec` Phase 0 | 项目根 |
| 能力图 | `/spec` Phase 0 | 项目根（**文件名未定义**） |
| `tasks/plan.md` | `/planning` | `tasks/` |
| `tasks/todo.md` | `/planning` | `tasks/` |
| `PERF.md` | `/webperf` | 项目根 |

---

## 三、关键源码位置

### 3.1 spec 查找规则 —— `commands/build.toml:30`

> Require a spec. Look only for a spec at a known path: SPEC.md at the repo root,
> docs/SPEC.md, or a file under spec/. A README or arbitrary doc does NOT count.
> If none exists, stop and tell the user to run /spec first — do not invent requirements.

**三条路径里只有 `spec/` 是通配的。** 这是 spec-guard 把 spec 放进 `spec/` 目录
而不是根目录的直接依据。

### 3.2 clean baseline 检查 —— `commands/build.toml:31`

> Establish a clean baseline. Run `git status --porcelain`. If there are uncommitted
> changes outside the expected planning artifacts (SPEC.md, docs/SPEC.md, spec/*,
> tasks/plan.md, tasks/todo.md), stop and ask the user to commit, stash, or confirm...

顺带确认了 `docs/SPEC.md` 和 `spec/*` 是上游认可的合法位置。

### 3.3 多模块 Phase 0 —— `skills/spec-driven-development/SKILL.md:38-65`

**触发条件**：

> - The requirement names distinct capabilities with their own consumers or data
>   (e.g. identity, billing, notifications, reporting)
> - Acceptance criteria cluster into groups that could ship and be verified separately
> - One capability could be cut or replaced without rewriting the others' requirements

**能力图格式**：

```markdown
# Capability Map: [Initiative Name]

| Module id | Responsibility | Depends on |
|---|---|---|
| identity | Accounts, sessions, SSO | — |
| billing | Plans, invoices, payments | identity |

Build order: identity → billing, notifications → reporting
```

**三条约束**（第 59-63 行）：

> - **Stable module ids.** Kebab-case, chosen once, never renamed mid-initiative.
> - **Dependency direction, no cycles.** If two modules each need the other, they are one module.
> - **The map is gated like every phase.** Getting the map wrong is expensive;
>   reviewing ten lines is not.

**递归与命名**（第 65 行）：

> Then recurse per module. Run Specify → Plan → Tasks → Implement for each module in
> dependency order. Each module gets its own spec... Save the approved map at the
> project root and each module's spec alongside it, named by module id
> (`SPEC-identity.md`, `SPEC-billing.md`) — **the map, not filename guessing, is the
> index of what exists.**

⚠️ **上游的一处自相矛盾**：它声称「是这张图构成了索引」，却**没有规定索引本身的
文件名**。spec-guard 固定为 `spec/CAPABILITY-MAP.md`。

⚠️ **上游的第二处不一致**：Phase 0 让 spec 放项目根并命名为 `SPEC-<module>.md`，
但 3.1 的查找规则匹配不到这个模式。

### 3.4 外部 tracker 扩展点 —— `skills/planning-and-task-breakdown/SKILL.md:150-157`

**这是 spec-guard 整个 GitHub 集成的立足点。**

> **Task List Target** — The task list target is where tasks and checkpoints are
> recorded. It is defined once, here; every other reference in this skill defers to it.
>
> - **Default: a checklist-style markdown file at `tasks/todo.md`.** This is the
>   convention the `/build` command and other downstream tooling expect.
> - **External tracker:** if the project's agent rules (`CLAUDE.md`, `AGENTS.md`, etc.)
>   or the user designate an issue tracker (e.g. GitHub Issues, Jira, Linear,
>   `bd`/beads), create one tracker item per task **instead of** writing `tasks/todo.md`.
>   Map the Step 4 structure onto the tracker's fields: acceptance criteria and
>   verification steps in the item body, dependencies via the tracker's linking
>   mechanism (`bd dep add`, "blocked by", etc.).
>
> When using an external tracker, note it in `tasks/plan.md` (e.g. "Tasks tracked in
> Linear project FOO") so downstream steps and future sessions know where to look,
> and keep the plan document's Task List section as an ordered index of tracker item
> IDs or links rather than a duplicate checklist.

**三条要点**：

1. `instead of` ≠ `in addition to` —— 二选一，不并存
2. 激活条件是「项目的 agent 规则**或用户**指定了 tracker」→ 写进 CLAUDE.md 即可激活
3. plan.md 要记录 tracker 位置，是跨会话续接的锚点

### 3.5 plan.md 不该进 tracker —— 同文件 Output Files 章节

> **Plan document:** Save the implementation plan to `tasks/plan.md`. This is always
> a markdown file — **design decisions, risks, and open questions don't map cleanly
> onto individual tracker issues.**

### 3.6 编排责任归属 —— `docs/agents.md:22, 55`

> The user (or a slash command) is the orchestrator. **Personas do not call other
> personas.** Skills are mandatory hops inside a persona's workflow.

决策矩阵：

> ```
> Is the work a single perspective on a single artifact?
> ├── Yes → Direct persona invocation
> └── No  → Are the sub-tasks independent (no shared mutable state, no ordering)?
>          ├── Yes → Slash command with parallel fan-out (e.g. /ship)
>          └── No  → Sequential slash commands run by the user
>                    (/spec → /plan → /build → /test → /review)
> ```

**这是「链路会断」的根本原因**：顺序编排显式交给人，没有任何自动推进机制。

### 3.7 竞品评价 —— `docs/comparison.md:48`

评价 `obra/superpowers` 时提到：

> Recent work is pushing from single-session skills toward multi-session orchestration
> through issue trackers (the in-progress `wayfinder`).

说明作者知道这个方向，但本套仍停在单会话模型。

### 3.8 planning skill 无 module 概念

```bash
grep -n -iE "module|capability map|per-module|SPEC-" \
  skills/planning-and-task-breakdown/SKILL.md
# → 无匹配
```

**确认缺口 B**：多模块递归时，各模块的 `/planning` 会互相覆盖 `tasks/plan.md`。

### 3.9 全仓库无 gh 调用

```bash
grep -rn -iE "\bgh (issue|pr|api)\b|github issues|issue tracker" \
  --include="*.md" --include="*.toml" .
```

有效结果只有 3.4 那一段。其余全部无关：

| 位置 | 内容 | 性质 |
|---|---|---|
| `AGENTS.md:88` `CONTRIBUTING.md:14` `docs/developer-onboarding.md:86` `.claude/rules/skills-contributing.md:11` | `gh pr list --state open` | 给**贡献本仓库的人**查重用 |
| `CLAUDE.md:47` | "Pull Requests" 章节 | 仓库自身规范 |
| `skills/ci-cd-and-automation/SKILL.md:29` | "Pull Request Opened" 流水线图 | CI 配置，非 issue 工作流 |
| `evals/cases/*.json` | "Review this pull request" | 测试用例 prompt |
| `docs/copilot-setup.md:17` | 链到 GitHub Copilot skills 文档 | 安装说明 |

**确认缺口 E**：没有任何 issue 读取、PR 创建、状态回写的实现。

---

## 四、hook 机制参考

`hooks/hooks.json` **只注册了一个 SessionStart**（这是 spec-guard 的 UserPromptSubmit
不与上游冲突的依据）：

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "SCRIPT=\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"; [ -f \"$SCRIPT\" ] || SCRIPT=\"${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start.sh\"; [ -f \"$SCRIPT\" ]&& bash \"$SCRIPT\" || true"
      }]
    }]
  }
}
```

**两个值得抄的模式**：

1. `${CLAUDE_PLUGIN_ROOT}` 与 `${CLAUDE_PROJECT_DIR}` 双路径回退
2. 末尾 `|| true` —— hook 失败绝不阻断会话

`session-start.sh` 的输出格式（spec-guard 的 UserPromptSubmit 沿用同一形状）：

```json
{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "..."}}
```

脚本注释里写着：*Hosts that validate hook output (Codex CLI, Claude Code) reject
other shapes.* —— **输出格式错了会被宿主拒绝，且失败是静默的。**

它对 `jq` 缺失有降级提示。spec-guard 更进一步，用 python3 兜底而不是仅提示。

⚠️ **注册 ≠ 目录内容。** `hooks/` 目录里另有 `sdd-cache-pre/post.sh`
（`source-driven-development` 的跨会话引用缓存，靠 HTTP `304` 重验而非读旧内容）
和 `simplify-ignore.sh`，但**都没有写进 `hooks.json`**，需要用户手动配置。
判断「上游有没有自动推进机制」时看 `hooks.json` 的注册项，不要数目录里的文件。

---

## 五、重新核对清单

上游更新后，按此清单验证 spec-guard 是否仍然成立。

先定位上游装在哪、是哪个 commit：

```bash
M=~/.claude/plugins/marketplaces/addy-agent-skills
git -C "$M" log -1 --format='%h %ad' --date=short
find "$M" -type f -not -path '*/.git/*' | wc -l    # 应为 187 上下
```

### 末次核对结果（2026-08-26 · commit `5a5ea45`）

| # | 核对项 | 结果 | 结论 |
|---|---|---|---|
| 1 | `build.toml:30` 仍是那三条路径 | ✅ 逐字未变 | 缺口 A 成立 |
| 2 | `Task List Target` 章节还在 | ✅ 在（行号 155→**150**） | GitHub 集成的地基存在 |
| 3 | 激活条件仍是「CLAUDE.md/AGENTS.md 或用户指定 tracker」 | ✅ 原文未变 | 声明块确为「接上游接口」 |
| 4 | planning skill 有了 module 概念？ | ❌ 仍 0 命中 | **缺口 B 仍成立** |
| 5 | 新增了 gh 调用？ | ❌ 无 | **缺口 E 仍成立** |
| 6 | 能力图有了固定文件名？ | ❌ 仍只说 "at the project root" | **已知限制 3 仍成立** |
| 7 | 新增了自动推进机制？ | ❌ `hooks.json` 仍只注册 1 个 SessionStart | **缺口 F 仍成立**，且不冲突 |

**五个缺口一个都没被上游补掉，插件整体成立。**

### 逐条怎么验

```bash
M=~/.claude/plugins/marketplaces/addy-agent-skills

# 1. spec 查找规则（只有 spec/ 是通配的）
sed -n '30p' "$M/commands/build.toml"

# 2-3. Task List Target 章节 + 激活条件
grep -n "Task List Target" "$M/skills/planning-and-task-breakdown/SKILL.md"
grep -n "External tracker" "$M/skills/planning-and-task-breakdown/SKILL.md"

# 4. planning 有 module 概念了吗（0 = 缺口 B 仍成立）
grep -c -iE "module|capability map|per-module|SPEC-" \
  "$M/skills/planning-and-task-breakdown/SKILL.md"

# 5. 新增 gh 调用了吗（排除贡献者查重用的 gh pr list）
grep -rn -E "\bgh (issue|pr) " "$M" --include="*.md" --include="*.toml" \
  | grep -viE "pr list --state open|copilot"

# 6. 能力图文件名（仍只说 project root = 已知限制 3 仍成立）
grep -n "Save the approved map" "$M/skills/spec-driven-development/SKILL.md"

# 7. 注册了哪些 hook 事件（不是数 hooks/ 目录里的文件）
python3 -c "import json;print(list(json.load(open('$M/hooks/hooks.json'))['hooks']))"
```

有任何一条翻转，对应功能就该撤掉或改为跟随上游 —— 见 [design.md 三、五个缺口与对策](design.md)。
