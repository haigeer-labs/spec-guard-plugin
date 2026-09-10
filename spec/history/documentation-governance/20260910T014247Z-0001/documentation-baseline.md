# Spec: documentation-baseline

## Objective

为启用 Spec Guard 的项目建立一份可引用、可解析、但不复制业务内容的文档基线。它让 Agent 在写模块 Spec 前知道哪些需求、架构和消费者文档是当前的上游约束，以及这些文档处于目标态、实施中、已验证、待决策或不适用的哪种状态。

该能力只在项目明确启用后工作。它不要求所有项目拥有 ADR、用户手册、接入文档或固定目录；也不通过代码、时间戳或 diff 推测任一文档是否过期。

## User-facing Contract

- Canonical artifact: `docs/DOCUMENTATION-BASELINE.md`.
- 基线是索引，不是需求、架构、ADR 或手册的副本；每项只引用其权威路径或外部 URL。
- 三项通用关注点必须由项目显式回答：`product-direction`、`architecture`、`developer-entry`。每项可指向一份既有文档、同一份 README 的不同章节，或在尚未建立时标为 `pending` 并说明原因。
- 条件性关注点包括 `consumer-guide`、`integration-contract`、`adr`、`operations`、`compliance`；它们只能以适用性和理由声明，不能被机械视为缺失。
- 有效状态仅为 `target`、`in-progress`、`verified`、`pending`、`not-applicable`。`target` 合法地表示已批准但尚未完全实现的架构或产品方向。
- 未启用时解析结果为 `absent`，调用方静默跳过；格式无效时返回具体事实，不创建、覆盖或猜测文档。

## Commands

```text
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
```

## Project Structure

```text
docs/DOCUMENTATION-BASELINE.md          -> 项目主动启用后的权威文档索引
plugins/spec-guard/hooks/               -> 标准库解析与只读事实收集
plugins/spec-guard/commands/            -> Claude 显式初始化/查询入口
plugins/spec-guard/skills/spec-guard-ops/ -> Codex 等价入口
```

## Testing Strategy

- 解析器测试有效最小基线、同一权威文档覆盖多项、外部 URL、目标态与不适用项。
- 反向测试覆盖缺失通用关注点、未知状态、重复关注点、空理由、损坏 Markdown 和未启用项目。
- 命令/宿主测试验证预览零写入；用户确认前不创建基线；已存在文件绝不被静默覆盖。
- 本模块不产生 Web UI；浏览器验收不适用。

## Boundaries

- Always: 把基线声明与它指向的业务文档区分开；把未知显示为未知；保留项目既有文档位置和格式。
- Ask first: 创建基线文件、覆盖既有基线、把 `pending` 改为已确认状态、把已有文档判为不适用。
- Never: 扫描代码认定架构文档过期；要求所有项目生成 ADR 或用户手册；把基线内容复制进 Issue、Plan 或 `.agent/state.json`；在未启用项目上发出告警。

## Success Criteria

- 项目可用一份简短、显式启用的基线声明其上游文档与状态，而无须迁移或重写既有文档。
- 解析器的结果区分 `absent`、`invalid` 与有效但 `pending` 的基线，不把三者混成“完成”或“失败”。
- 已批准但未完全实现的目标架构可被表达为 `target`，且不会被视为文档与代码矛盾。
- 所有解析和预览路径只读；实际创建必须经用户确认。

## Open Questions

None for V1. 外部文档系统的认证、同步和内容质量评估均不在范围内。
