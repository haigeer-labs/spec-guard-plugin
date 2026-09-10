# Spec: documentation-impact

## Objective

让已显式启用文档基线的项目，在每个模块开始实现前说明其与上游文档的关系，并在计划中收口需要更新或新建的文档交付物。它将“文档是否受本模块影响”从隐含假设变成可审阅的决定，但不把文档当作代码的派生产物。

## User-facing Contract

- 仅当 `docs/DOCUMENTATION-BASELINE.md` 有效时，模块可使用 `## Documentation impact` 决策表；基线未启用时结果为 `absent`，不是违规。
- 适用的基线关注点必须逐项选用 `follow`、`update`、`create`、`pending` 或 `not-applicable`，并说明理由。`not-applicable` 是模块级无影响，不改变项目级基线的适用性。
- `follow` 表示该模块遵循权威文档但不在本模块改写它；`update` 与 `create` 表示有明确的文档交付物；`pending` 保留尚未决定的事实，绝不被伪装成完成。
- 选择 `update` 或 `create` 时，模块 Plan 的 `## Documentation delivery` 表必须声明对应的预期交付物和理由；这是一项计划事实，不是“文档已经真实更新”的断言。
- 解析器只读取基线、模块 Spec 和模块 Plan，返回 `absent`、`invalid` 或有效事实；不扫描代码、Git diff、时间戳或文档正文来推断真实状态。

## Commands

```text
python3 -B plugins/spec-guard/hooks/test_documentation_impact.py
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash scripts/validate.sh
```

## Project Structure

```text
docs/DOCUMENTATION-BASELINE.md          -> 项目级上游文档基线（前置模块）
spec/<module-id>.md                     -> 模块的 Documentation impact 决策表
tasks/<module-id>/plan.md               -> update/create 的 Documentation delivery 计划表
plugins/spec-guard/hooks/               -> 只读跨产物解析器与回归测试
plugins/spec-guard/commands/            -> Claude 显式查询/草稿入口
plugins/spec-guard/skills/spec-guard-ops/ -> Codex 等价入口
```

## Testing Strategy

- 覆盖未启用、有效基线、模块级完整决策、待决与不适用项。
- 覆盖缺失决策、未知决定、重复关注点、空理由、缺失交付计划以及无关的 fenced Markdown 示例。
- 覆盖 `update`/`create` 与 Plan 交付条目的一一对应；禁止从文件内容或 Git 状态推断文档是否已完成。
- 本模块不产生 Web UI；浏览器验收不适用。

## Boundaries

- Always: 让每个决定可追溯到基线中的关注点；保留 `target`、`pending` 和“模块无影响”的明确表达；把计划交付和实际出版分开。
- Ask first: 为既有模块 Spec 或 Plan 新增/更改决策表；把 `pending` 改为其他决定；声称 `update` 或 `create` 已交付。
- Never: 通过代码或 diff 猜测文档过期；要求每个模块创建 ADR、用户手册或接入文档；自动修改权威业务文档；把提醒升级为开发阻断。

## Success Criteria

- 已启用项目的模块可明确展示其对每项适用上游文档的关系，而未启用项目保持安静。
- 需要修改或创建文档的决定会在计划层拥有对应交付物，而不是仅留在口头提醒。
- 待决和不适用结论均带理由，且不会被报告为文档已完成。
- 所有查询路径只读，输出不就文档内容或代码实现作未经用户确认的结论。

## Open Questions

本模块只定义计划层事实。交付前的保守提醒、证据呈现与跨宿主核验由 `documentation-verification` 处理。
