# Spec: documentation-verification

## Objective

在交付收口前提供文档治理的只读核验：把基线、模块影响决定、计划交付物和人工声明的结果汇总为保守提醒。它要明确区分“未启用”“结构无效”“仍待决”“已声明交付”，但不声称已经验证了业务文档的真实内容或代码符合度。

## User-facing Contract

- 查询对象是一个模块；基线未启用时返回 `absent`，不告警。
- 有效影响记录中的 `pending`、`update`/`create` 尚无结果、或结果为 `pending`/`deferred` 时返回 `attention`，不阻止开发或远端交付命令。
- 需要更新或创建文档的模块，在交付前可在 Plan 的 `## Documentation outcome` 表中声明 `delivered`、`deferred` 或 `pending`。`delivered` 必须给出用户提供的证据指针；`deferred`/`pending` 必须给出理由。
- `ready` 只表示没有未收口的**声明性**文档事项；它绝不证明指针真实、文档内容正确、代码实现一致，或文档已经对外发布。
- `/verify-artifacts` 仅显示这项事实；`attention` 是提醒而非失败。任何文档实际写入仍遵守用户确认。

## Commands

```text
python3 -B plugins/spec-guard/hooks/test_documentation_verification.py
CLAUDE_PROJECT_DIR="$PWD" /bin/bash plugins/spec-guard/hooks/verify-artifacts.sh
/bin/bash scripts/validate.sh
```

## Testing Strategy

- 覆盖未启用、有效但待决、计划交付未收口、交付声明、延后声明与无效表格。
- 覆盖 `delivered` 缺证据、重复行、未知结果和 fenced 示例表格。
- 覆盖 verify-artifacts 显示提醒但不把 `attention` 计为失败；Claude/Codex 入口保持一致。
- 本模块不产生 Web UI；浏览器验收不适用。

## Boundaries

- Always: 把计划、人工声明、真实性验证分层呈现；保留不确定性；仅在显式核验调用中输出提醒。
- Ask first: 增加或改变 outcome 声明；把 pending/deferred 改为 delivered；修改业务文档。
- Never: 扫描代码或 Git diff 断言文档已更新；把 self-reported evidence 当作内容验证；把 attention 升格为编码或交付的硬阻断。

## Success Criteria

- 交付前能够看见文档事项是待决、延后还是已声明交付，且三者不混淆。
- 没有基线的项目不受影响；无效结构清楚报错。
- 核验输出不会把任何未声明或未知事项说成已完成。

## Open Questions

外部文档系统的内容审查、链接可访问性和发布审批不在 V1 范围内。
