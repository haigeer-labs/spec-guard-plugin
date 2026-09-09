# 真实验收旅程

这些旅程用于补足本地回归无法证明的安装、宿主和项目行为。它们是**手动、按次确认**的
验收方案，不是自动化执行器，也不会由插件自行创建 worktree、Issue、PR 或 MR。

开始任一旅程前，必须逐次获得用户确认，并写明：目标身份、允许的写入范围、预期副作用、
执行者、观察时间和原始证据。未获确认、目标不可用或执行中断时，记录 `not-verified` 与
原因；不得将命令退出 0 写为通过。

## GitHub 测试仓库

仅使用用户明确批准的、可写的 GitHub 测试仓库。记录完整的 `owner/repository`，并在开始前
列出允许创建或修改的 Issue、分支、PR 和标签范围。建议顺序为：

1. 新项目首次安装后执行 `/setup-convention`，记录生成的约定和能力图目标。
2. 创建一个具备依赖和一个可并列 build order 的小型能力图，验证同步、取任务、交付和历史
   回溯只作用于该命名仓库。
3. 重复运行与中断恢复各一次，记录是否出现重复 Issue、错误的活动模块或不应有的写入。
4. 如需验证双 worktree，按本页“手工 worktree”旅程执行；不要由 Spec Guard 自动分派写任务。

只有所有允许的副作用和证据都已记录时，旅程才可用 `project-verified`；其
`target.kind` 为 `tracker-project`。

### 标准验收项目（用户长期指定，2026-09-09）

以下三个私有 GitHub 仓库是 Spec Guard 的固定测试目标。后续与其职责相符的验收不再重复询问
仓库身份；不得将这项授权扩展到其他仓库或生产项目。

| 仓库 | 默认职责 | 路线图验收角色 |
| --- | --- | --- |
| `yizhongkaimail-collab/spec-guard-e2e-new-20260903` | 新项目接入、能力图和 GitHub tracker 旅程 | 正向主项目：验证唯一 Initiative、依赖/后继、`--all` 与只读 tracker overlay。 |
| `yizhongkaimail-collab/spec-guard-e2e-upgrade-20260903` | 旧项目升级 | 负向兼容项目：没有活跃 Initiative 时不得猜测当前位置。 |
| `yizhongkaimail-collab/spec-guard-e2e-sync-v0729-20260903` | 旧版 GitHub 同步兼容 | 负向兼容项目：缺 state/能力图时路线图必须保守降级，不能从遗留 spec/plan 伪造进度。 |

在上述项目中，常规验收可创建带 `e2e` 前缀的测试 Issue、分支与 Draft PR，并可为已声明的
验收步骤更新其 `.agent`、能力图、Spec 或 Plan。保留原始证据和测试产物；删除仓库、重写历史、
修改插件发布标签或操作其他仓库仍须单独确认。实际写入前仍在发布证据中记录目标、时间、范围和
副作用，不把“测试仓库已指定”误报为“该次旅程已通过”。

## GitLab 测试仓库

仅使用用户明确批准的 GitLab 测试仓库，并记录完整的 GitLab URL、项目路径和允许的 Issue/MR
写入范围。按 GitHub 相同的首次使用、重复运行和中断恢复顺序进行，但必须单独保存证据；
GitHub 的结果不能升级为 GitLab 的结果。GitLab 不提供的对象或权限不足时保留
`not-verified`，不以 GitHub 行为替代。

## 两个手工创建的不同 worktree

在用户确认的同一 Git 仓库中，由执行者先创建两个**不同路径、不同分支**的 worktree。记录
仓库、两个绝对路径、两个分支、共同基点和允许修改的文件边界。然后在两个独立 Agent/宿主
会话中执行已确认的、无交叉文件边界的任务，并人工检查：

- 每个会话的 `git status`、分支和工作目录都与其记录一致；
- 任一会话没有读取或写入另一个 worktree 的状态文件、计划或未提交内容；
- 汇合前完成差异审查、测试和冲突处理；失败时停止并留下 `not-verified` 或失败证据。

这证明的是已人工隔离的双 worktree 流程，不证明自动并行执行、自动任务创建或自动回收。
已完整观察时，旅程使用 `host-verified` 和 `worktree-pair` 目标；否则保持 `not-verified`。

## 新安装和降级环境

新安装需记录包版本、安装来源、全新的宿主会话身份、加载结果与命令/界面证据；通过时使用
`installed-verified` 和 `installed-session` 目标。安装、升级和桌面会话启动均需先确认。

离线、未认证、缺插件或没有可用桌面会话属于降级环境：确认其没有越界写入后，记录环境身份、
预期副作用和 `not-verified` 原因。它们绝不能生成“支持该宿主”或“项目验收通过”的结论。

## 记录方式

将旅程附在版本证据 JSON 的可选 `journeys` 数组中，并运行：

```bash
python3 scripts/release-evidence.py validate docs/releases/<version>-<target>.json
```

每个 journey 都必须包含唯一 `id`、受限 `kind`、`confirmation: "required"`、命名
`target`、非空 `expectedSideEffects` 和状态。未验证旅程必须有 `reason`，且不得附带
`observedAt` 或 `evidence`；已验证旅程必须有时间和原始证据引用。
