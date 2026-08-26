# spec-guard

给 `addyosmani/agent-skills` 补三样东西的 Claude Code 插件：

1. **多模块 Spec 支持** —— 上游 `/spec` 支持多 spec，但 `/planning` 和 `/build` 没跟上
2. **GitHub Issue 打通** —— 上游内置了 External Tracker 分支，但零 `gh` 实现
3. **链路断裂检测** —— 上游把顺序编排的责任交给了人，没人推进就断在半路

---

## 安装

```
/plugin marketplace add <你的仓库地址>
/plugin install spec-guard
```

然后**在每个要用的项目里跑一次**：

```
/setup-convention github     # 或 local
```

---

## 为什么需要两步

这是本插件设计上最重要的一点：

```
插件      = 装给「你这台机器」的工具       · 每人各装各的
项目约定  = 提交给「整个项目」的规范       · 必须进 git，全队共享
```

插件能带 hook、skill、命令，**但不能往你的仓库写文件**。而下面这些必须在仓库里：

| 文件 | 为什么必须在仓库 |
|---|---|
| `CLAUDE.md` 声明块 | **它是激活 agent-skills 内置 External Tracker 分支的开关**。不在仓库里，队友的 `/planning` 还是写 todo.md |
| `spec/` `tasks/` | 目录约定，全队一致 |
| `.agent/state.json` | 跨会话、跨成员的进度锚点 |

所以 `/setup-convention` 不是多余的一步——它是把「个人工具」和「团队约定」连起来的那一步。

---

## 提供的能力

### 命令

| 命令 | 作用 |
|---|---|
| `/setup-convention [github\|local]` | 在当前项目落地约定（首次跑一次） |
| `/phase` | 查看当前链路状态和断链项 |
| `/sync-map` | 能力图 → GitHub Issue 结构 |
| `/next` | 从 GitHub 取下一个可执行任务 |
| `/deliver` | 五轴自查 → 开 PR（Closes #n） |

### Hook

`UserPromptSubmit` 上挂一个 187 行的探测脚本。**每次你发言前**注入仓库真实状态：

```markdown
## agent-skills 链路状态（自动探测，非用户输入）

当前阶段: **TRACKED**
  - tracker: github
  - 活跃模块: identity (issue #101)
  - spec: 能力图=true, 模块 spec=3 份
  - plan: tasks/identity/plan.md=false

**检测到断链：**
  ⚠ 模块 [identity] 有 spec 和 issue，但没有 plan.md —— 链路在此断开

建议下一步: /planning 为 [identity] 拆解任务
```

### Skill

`spec-github-bridge` —— 能力图落库、任务落库、取任务、交付四个操作的完整流程。

---

## 核心设计：状态注入，不是意图分类

「说了需求但没触发对应 skill」这个问题，很多人的第一反应是加一层路由。

**这行不通** —— 路由 skill 自己也要靠 description 触发，是同一个问题。

本插件的做法是注入**确定性事实**：文件在不在、issue 有没有、分支干不干净。模型看得见缺什么，路由自然就准，而且断链在下一轮对话开头就暴露，不需要人记得检查。

| | 路由 skill | 状态注入 hook |
|---|---|---|
| 触发可靠性 | 靠 description 匹配 —— 同样的问题 | 100%，hook 强制执行 |
| 断链检测 | 只在被调用时 | 每次发言 |
| 上下文成本 | 整个 skill 常驻 | ~200 token |
| 出错影响 | 跑错流程 | 最坏多说一段状态 |

---

## 三个安全设计

**① 默认不生效**

hook 开头检查 `CLAUDE.md` 是否含 `Agent Skills 集成约定`。没有就静默退出——所以装了插件也不会污染你其他项目。

**② 探测失败就降级，不误报**

- `gh` 没装/没登录/离线 → 退化为本地判定，标注 `(gh 不可用，降级判定)`
- 远端是 GitLab/Gitee → `tracker: other`，只检查 spec/plan 层，**不碰任务层**
- 无 remote → 自动本地模式

早期版本在 GitLab 项目上会永远误报「没建 issue」。**假断链比不报断链危害大得多**——它会让人几天内就关掉整个机制。

**③ 不越权**

断链的处理规则写死成「先说明、得到确认后再执行」。断链可能是你故意的（这个模块暂时不做 plan）。

---

## 三种 tracker 模式

判定顺序：`state.json` 的 `tracker` 字段 → git remote 域名推断 → `none`

| 模式 | 任务清单在哪 | 检测范围 |
|---|---|---|
| `github` | GitHub Issues | 完整（含任务层） |
| `none` | `tasks/<module>/todo.md` | 完整（Addy 原生路径） |
| `other` / `gitlab` / `jira` | 你自己的系统 | 只到 plan 层 |

**目录约定三种模式完全一样**，只有任务层落点不同。所以从 `none` 迁到 `github`，`spec/` 和 `plan.md` 一个字不用改。

> 不确定的话**先用 `local` 跑两周**，验证多模块拆分本身跑不跑得通，再决定要不要上 issue。

---

## 前置要求

| | |
|---|---|
| `python3` | 必需（hook 的 JSON 解析） |
| `git` | 必需 |
| `gh` ≥ **2.94.0** | GitHub 模式必需 |

⚠️ **光看 `gh --version` 不够**。`/setup-convention` 会额外验证：

```bash
gh issue create --help | grep -- "--parent"
```

PATH 里有多个 `gh` 时，版本号可能来自新的、实际执行的是旧的。这个失败很隐蔽——批量执行时只看到一堆 `unknown flag`，很难定位根因。

---

## 测试

```bash
bash plugins/spec-guard/hooks/test-phase-guard.sh
```

12 个场景：

```
✅ 空仓库 / 只有能力图 / spec无issue / 根目录SPEC
✅ todo并存 / 干净待交付 / 有改动
✅ 未启用仓库静默 / 目录不存在不崩
✅ 本地模式齐全 / 本地模式缺plan / GitLab未声明
```

---

## 装完的关键验证点

跑完 `/setup-convention` 和 `/planning` 之后，**看它到底建 issue 还是写 todo.md**。

这是整套方案能否成立的分水岭：

- 建了 sub-issue → Addy 内置的 External Tracker 分支被正确激活，后面的自动化才有意义
- 还在写 todo.md → 先调 `CLAUDE.md` 的措辞，别急着往下走

---

## 依赖关系

本插件**依赖 `addyosmani/agent-skills` 已安装**。它补的是那套 skill 的缺口，不是替代品。

```
/plugin marketplace add addyosmani/agent-skills
/plugin install agent-skills@addy-agent-skills
/plugin install spec-guard
```

两者的 hook 并存不冲突（一个 SessionStart，一个 UserPromptSubmit）。
