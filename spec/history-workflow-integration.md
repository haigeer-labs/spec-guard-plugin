# Spec: history-workflow-integration

## Objective

将 initiative lifecycle、历史校验与迁移能力接入 Claude/Codex 宿主入口、文档与完整回归，保持确认和只读语义一致，不复制业务逻辑。

## Commands

```bash
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
```

## Contract

- 只读历史校验与迁移 preview 可直接运行。
- lifecycle 与迁移 import 均先要求用户确认。
- 所有入口只调用对应共享 hook 脚本。

## Testing Strategy

- Codex adapter 断言所有历史入口存在并指向共享脚本。
- 总校验覆盖全部历史模块回归。

## Boundaries

- Always: 复用共享脚本；保留确认语义。
- Ask first: 添加会改变用户项目文件的入口。
- Never: 在宿主 skill 中复制账本、验证或迁移逻辑。

## Success Criteria

1. Claude/Codex 可安全发现并调用三类历史能力。
2. 所有历史回归纳入总校验。
3. 文档说明预览、确认导入与只读校验的区别。
