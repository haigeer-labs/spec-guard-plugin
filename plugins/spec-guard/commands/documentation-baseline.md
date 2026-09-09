---
description: 预览或建立项目级文档基线，不自动生成或覆盖业务文档
allowed-tools: Bash, Read, Write
---

这是显式、预览优先的文档治理入口。文档基线只索引需求、架构和使用文档的权威位置与状态；它不从代码推断文档是否过期，也不复制业务内容到新文件。

先运行只读查询：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
python3 -B "${CLAUDE_PLUGIN_ROOT}/hooks/documentation_baseline.py" --project "$PROJECT" --format json
```

- `absent`：说明项目尚未启用文档基线。询问并展示最小草稿，覆盖 `product-direction`、`architecture`、`developer-entry`；只有用户明确确认后，才创建 `docs/DOCUMENTATION-BASELINE.md`。
- `valid`：逐项展示权威来源、状态与理由。`target` 是合法的目标态，不得拿代码或 Git diff 判定它过期。
- `invalid`：原样说明错误与协议路径 `references/documentation-baseline.md`；得到确认后才修改既有文件。

初始化或更新时，先读项目既有 README、需求、架构和 ADR 约定；引用它们的原有路径，不迁移、不覆盖，也不强制创建 ADR、用户手册或接入文档。外部文档可保留 URL。`not-applicable` 必须有具体理由。
