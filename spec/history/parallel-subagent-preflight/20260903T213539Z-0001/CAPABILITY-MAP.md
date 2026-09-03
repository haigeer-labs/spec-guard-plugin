# Capability Map: Native Subagent Parallel Preflight

> 由 `/spec` 的 Phase 0 产出。**必须经人工评审后才能往下走。**

## 目标

在 Spec Guard 已确认模块边界互不冲突后，为 Codex 提供一个经用户明确确认才会执行的
原生子智能体预检流程。预检只并行审查模块边界、实施计划与测试风险，并由父会话汇总；
它绝不把共享工作目录中的子智能体当作隔离 worktree，也绝不自动并行写入代码、创建
worktree、分支、Issue 或 Pull Request。

<!-- 这一段是 Epic issue 正文摘要的唯一来源，也是它的指纹底本。 -->

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| parallel-subagent-preflight | 在 Codex 专用操作 Skill 中把合格安全门结果转为经确认的只读原生子智能体预检、父会话汇总与宿主降级说明 | — |

Build order: parallel-subagent-preflight

---

## 评审记录

- [x] 模块边界确认（只增加只读预检，不接管写入型并行或 worktree 生命周期）
- [x] 依赖方向单向无环（既有 safety gate 已合入，是外部前置能力而非本 initiative 模块）
- [x] module id 已定稿（kebab-case，后续不改名）
- [x] 构建顺序符合依赖拓扑

评审人：用户（对话确认）
日期：2026-09-04
