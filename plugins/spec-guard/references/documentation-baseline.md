# 项目文档基线协议

文档基线是**显式启用**的项目级索引：它说明哪些已有文档构成项目的上游指导，以及每项处于何种状态。它不复制需求、架构或手册内容，更不根据代码、时间戳或 Git diff 推断文档是否过期。

未创建 `docs/DOCUMENTATION-BASELINE.md` 的项目视为未启用；检查器必须静默跳过，不能把它当作违规。

## 文件格式

文件必须恰好包含一张下列四列表格。表格外可保留人工说明。

```markdown
| Concern | Authority | Status | Rationale |
|---|---|---|---|
| product-direction | `docs/product.md` | verified | 已确认的目标、用户与成功标准。 |
| architecture | `docs/architecture.md` | target | 已批准的目标态尚未完全实现。 |
| developer-entry | `README.md` | verified | 构建、测试和开发入口已核对。 |
| consumer-guide | — | not-applicable | 当前没有受支持的终端用户。 |
```

`Authority` 可以是仓库相对路径或外部 URL；`not-applicable` 必须使用空值、`-` 或 `—`，并给出具体理由。其他状态必须引用权威来源。

## 关注点与状态

必须恰好声明一次的通用关注点：

- `product-direction`：目标、用户、成功标准与范围边界；
- `architecture`：技术边界、约束和演进方向；
- `developer-entry`：构建、测试和维护入口。

可按项目特征声明的关注点包括 `consumer-guide`、`integration-contract`、`adr`、`operations` 与 `compliance`。

允许状态：

- `target`：已确认的目标态，允许尚未完全落地；
- `in-progress`：正在实施或补全；
- `verified`：已有相应实现或演练证据；
- `pending`：尚未形成结论；
- `not-applicable`：经明确判断不适用。

每一行的 `Rationale` 都必须非空。它解释该文档为何是指导来源、为何仍属目标态，或为何不适用；这防止“没写”被误当作“无需写”。
