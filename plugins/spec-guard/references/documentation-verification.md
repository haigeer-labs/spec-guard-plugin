# 文档交付核验协议

此协议汇总模块已经**声明**的文档结果。它不会检查文档正文、链接可访问性、外部发布状态或代码符合度；`ready` 因而只能表示声明层没有未收口项。

仅在项目有有效文档基线、且模块影响表有效时使用。没有基线的项目结果为 `absent`，不会收到提醒。

## Plan outcome 表

当模块的 `Documentation impact` 中存在 `update` 或 `create` 时，可在同一模块 Plan 中写一张：

```markdown
## Documentation outcome

| Concern | Outcome | Evidence | Rationale |
|---|---|---|---|
| architecture | delivered | `docs/architecture.md#module-boundary` | 边界已由架构负责人确认。 |
| integration-contract | deferred | — | 等待外部 API 评审。 |
```

`Outcome` 仅可为：

- `delivered`：必须给出用户提供的证据指针；该指针不是自动验真的结果；
- `deferred`：必须说明为何没有在本模块交付；
- `pending`：必须说明待决原因。

表只可包含对应的 `update`/`create` 关注点，且每项至多一行。

## 核验状态

- `absent`：没有启用文档基线；
- `invalid`：基线、影响记录或 outcome 结构无效；
- `attention`：存在模块级 `pending`、尚未声明 outcome、或 outcome 为 `deferred`/`pending`；
- `ready`：所有需交付项均已声明 `delivered`，且没有待决决定。

`attention` 是提醒，不是开发、Issue 或 PR 的硬阻断。`ready` 不得解释为“文档正确”“文档已发布”或“代码实现符合文档”。
