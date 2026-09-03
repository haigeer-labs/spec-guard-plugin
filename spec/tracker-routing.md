# Spec: Tracker Routing

## Objective

让 Spec Guard 的 hook、初始化器与命令在 GitHub、GitLab 和本地项目中选择正确的 bridge，
并确保任何 GitHub 专属命令不会在 GitLab 项目执行。

## Commands

```bash
bash plugins/spec-guard/hooks/test-phase-guard.sh
bash plugins/spec-guard/hooks/test-verify-artifacts.sh
bash scripts/validate.sh
```

## Testing Strategy

- 对三种 tracker 断言命令提示和校验路径。
- GitLab 初始化必须输出 GitLab bridge 和 GitLab Issues。
- GitHub 现有 bridge 与本地 todo 流程不回归。

## Boundaries

- Always: 显式 tracker 优先，未知远端回退本地。
- Never: 在 GitLab 分支调用 `gh`，或在 GitHub 分支调用 `glab`。

## Success Criteria

1. GitLab 初始化、phase 和命令提示均指向 GitLab bridge。
2. GitHub 和本地现有输出不变。
3. 全量 shell 回归通过。
