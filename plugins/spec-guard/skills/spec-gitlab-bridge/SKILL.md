---
name: spec-gitlab-bridge
description: 在 Spec Guard 产物与 GitLab Issues、Merge Requests 之间执行安全的 GitLab 工作流。
---

# Spec Guard GitLab Bridge

## 前置检查（每次远端写入前）

```bash
glab auth status
glab repo view
```

API 必须可用；认证失败时停止，不要回退到 `gh`。读取 `.agent/state.json`，确认
`tracker` 是 `gitlab`；不是时停止，不要在 GitHub 或本地项目调用 `glab`。

```bash
PROJECT=$(glab repo view --output json | python3 -c \
  'import json,sys; d=json.load(sys.stdin); print(d["path_with_namespace"])')
PROJECT_ID=$(glab api "projects/${PROJECT//\//%2F}" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["id"])')
```

所有远端写入前先向用户列出将要创建或合并的 Issue / MR；删除、关闭非本次创建的
Issue/MR、重写远端历史时必须先得到确认。

## GitLab 15.3 能力边界

- Issue 与 Merge Request 可用。
- Issue link 只能建立 `relates_to`；它不是父子或阻塞关系。
- Work Items、父子 Issue、`--parent`、`--blocked-by` 不可依赖；不以 label 模拟。

## 目录与状态约定

| 对象 | 位置 | 规则 |
|---|---|---|
| 能力图 | `spec/CAPABILITY-MAP.md` | 唯一模块索引 |
| 模块 spec | `spec/<module-id>.md` | 只读为实现输入 |
| 模块计划 | `tasks/<module-id>/plan.md` | 保留计划，不复制成第二份任务清单 |
| 远端任务真源 | GitLab Issues | initiative、模块和 task 都是平面 Issue |
| 状态 | `.agent/state.json` | `initiative.issue`、`modules.<id>.issue`、`activeModule` 逐项写回 |

GitLab 15.3 没有可依赖的 Work Items 层级。模块 Issue 与 task Issue 的关联只能写入
正文并可选建立 `relates_to`；**绝不**把它称为父子、阻塞或执行顺序。

## 操作一：`/sync-map` 能力图落库

1. 读取能力图、`build order` 和 `.agent/state.json`。若 `initiative.issue` 已存在，先报告
   现有投影并询问用户选择“补充、刷新或新建”；不默认重复创建。
2. 为 initiative 创建一条普通 Issue；正文只写目标、能力图路径和
   `<!-- spec-guard-sync:initiative -->` 标记，不粘贴整份能力图。
3. 按 build order 为每个模块创建一条普通 Issue；正文写模块责任、spec 路径、计划路径、
   initiative IID 和 `<!-- spec-guard-sync:module:<id> -->` 标记。
4. 每创建成功一条 Issue，立刻把 IID 写回 `.agent/state.json`；不要等全部成功才写。
   失败后保留已写回的映射，重新执行时从第一个缺失项续跑。
5. 如需在 GitLab UI 中可见关联，使用 `relates_to`，并在输出中注明它只是关联；不要用
   label、标题前缀或 `relates_to` 模拟依赖。
6. 全部模块映射成功后才把 `activeModule` 设为 build order 的第一个模块。把本次映射
   摘要、Issue IID 和降级说明写入用户可审阅的输出。

创建 Issue 与关联只能通过下列受限入口或等价的显式 `glab` 命令：

```bash
glab issue create --repo <group/project> --title '<title>' --description-file <file>
glab api -X POST 'projects/<project-id>/issues/<iid>/links' \
  -f target_project_id=<project-id> -f target_issue_iid=<iid>
glab mr create --repo <group/project> --source-branch <branch> --target-branch <branch>
glab mr merge <iid> --repo <group/project> --yes --remove-source-branch
```

始终在输出中标明 `relates_to` 是降级关联。未知 API 版本或 404 时停止并说明该能力不可用。

对刚创建的 MR，GitLab 15.3 可能短暂返回 422，但随后状态仍为 `opened`、
`can_be_merged` 且无冲突。只能通过受限入口处理这一情形：

```bash
/bin/bash "$ROOT/hooks/gitlab-bridge.sh" merge --repo <group/project> --iid <iid>
```

它只会在首次失败后读取远端状态，并且**仅**在上述三个条件同时满足时重试一次；
其他失败不得重试或绕过保护。

## 操作二：`/plan` 后任务落库

`plan.md` 是设计与实现步骤，不是远端 task 的第二份副本。对每个可独立执行的步骤创建
一条平面 GitLab Issue，正文必须包含模块 IID、计划路径和
`<!-- spec-guard-task:module=<module-id> -->` 标记。创建成功后在 `plan.md` 用
`> Tasks tracked in GitLab Issues: #<iid>, ...` 记录远端索引；不要写 checkbox。

创建 task 前先检查模块 Issue 仍为 `opened`。若 task 创建中断，逐条查询已有标记和 IID，
只补缺失项；不因状态不完整就重新建一套。任务之间没有可用的阻塞边时，按 `plan.md`
的顺序提出候选，并明确这是计划顺序、不是 GitLab 强制依赖。

## 操作三：`/next` 选择下一个任务

读取 `.agent/state.json` 的 `activeModule` 与对应的 `modules.<id>.issue`，再用
`glab api 'projects/<project-id>/issues/<iid>'` 确认该 Issue 仍为 `opened`。从该模块
`plan.md` 的 GitLab Issue 索引中逐条查询：只选择 `opened` 的 task，按计划出现顺序给出
一个候选。打开时才进入 `/build`；关闭、缺失或无法查询时停止并要求刷新 state。不要把
`relates_to` 当作依赖排序依据。

当没有打开的 task 时，先向用户展示模块 Issue 与 task 的关闭状态。确认模块已完成后才
关闭模块 Issue、推进 `activeModule` 到 build order 的下一项，并立即写回状态；最后一个
模块完成时，先要求用户确认，再关闭 initiative 并执行 capability history 的 complete
流程。

## 操作四：`/deliver` 模块级 Merge Request

1. 先执行 `code-review-and-quality` 的五轴检查和仓库测试；失败时不要创建 MR。
2. 确认当前分支仅属于 `activeModule`，工作区干净，并将本模块关闭 task 的 IID 写入
   commit 或 MR 描述（例如 `Closes #<iid>`）。不要关闭其他模块的 Issue。
3. 创建指向默认分支的模块级 MR，向用户显示 MR IID、源/目标分支和将自动关闭的 Issue。
4. 用户允许合并后，使用 `glab mr merge ... --remove-source-branch`。合并后逐条核对 task
   与模块 Issue 的状态；GitLab 没有自动关闭时，先说明并请求关闭授权。
5. 只有远端状态已核实后才推进 `activeModule` 或调用 initiative lifecycle。归档只移动
   本插件的 `spec/`、`tasks/` 和 `.agent/` 产物；不得删除用户业务文件。

## 失败与安全边界

- API 失败、认证失效、Issue/MR 不存在或状态无法读取时停止；不要回退到 `gh` 或本地
  todo 流程，也不要猜测成功。
- `relates_to` 始终标为降级关联，不能作为任务排序或完成条件。
- 不输出 token、认证配置或 `glab auth status` 的敏感细节。
- 结束时报告：项目、创建/更新的 Issue 与 MR IID、当前模块、是否有降级关联，以及
  下一步需要的用户确认。
