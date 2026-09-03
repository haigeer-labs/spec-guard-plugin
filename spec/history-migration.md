# Spec: history-migration

## Objective

从旧根目录 spec/plan、旧 state 与 Git 历史生成可审阅的 initiative 迁移预览；仅在用户确认后保守导入账本记录，失败不破坏原文件。

## Commands

```bash
/bin/bash plugins/spec-guard/hooks/test-history-migration.sh
/bin/bash scripts/validate.sh
```

## Project Structure

```text
plugins/spec-guard/hooks/history-migration.py
plugins/spec-guard/hooks/test-history-migration.sh
spec/CAPABILITY-HISTORY.json
```

## Contract

- `preview` 只读输出候选 initiative、checkpoint 与冲突。
- `import` 需要明确确认；账本目标已存在或证据模糊时拒绝写入。
- 导入使用账本工具的原子写入，不修改旧 spec、plan、state 或 Git 历史。

## Testing Strategy

- 有效旧项目生成稳定预览。
- 缺失或模糊证据不被猜测导入。
- 冲突、写入失败与未确认导入均不改现有产物。

## Boundaries

- Always: 先预览、先验证、仅追加新账本。
- Ask first: 执行 import。
- Never: 删除旧项目文件；将未知状态标为 completed。

## Success Criteria

1. 可审阅地识别可迁移旧证据。
2. 迁移失败零破坏，成功后账本可验证。
