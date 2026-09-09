---
description: 预览模块对文档基线的影响与计划交付物，不根据代码推断文档状态
allowed-tools: Bash, Read, Write
---

这是模块级、预览优先的文档影响入口。它把模块对上游需求、架构和消费者文档的决定写成可审阅事实；它不检查代码是否遵循文档，也不把计划中的文档交付物说成已经出版。

先确定模块 id，再只读查询：

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MODULE="<module-id>"
python3 -B "${CLAUDE_PLUGIN_ROOT}/hooks/documentation_impact.py" \
  --project "$PROJECT" --module "$MODULE" --format json
```

- `absent`：项目未启用文档基线，静默说明此入口没有约束；不要要求模块补表。
- `valid`：展示每项决定及 `update`/`create` 的计划交付物。`pending` 和 `not-applicable` 都是未被隐去的决定，不代表交付完成。
- `invalid`：原样说明错误与协议路径 `references/documentation-impact.md`；先展示依据用户提供事实形成的 Spec/Plan 草稿。

只有用户明确确认后，才把草稿写入或修改 `spec/<module-id>.md` 与 `tasks/<module-id>/plan.md`。先保留既有 Spec、Plan、业务文档和目录惯例；不得扫描代码、Git diff、文件时间或文档正文来推断文档是否过期、已更新或已被实现。不要自动创建 ADR、使用手册或接入文档；`update`/`create` 仅表示计划交付物，实际交付由后续核验处理。
