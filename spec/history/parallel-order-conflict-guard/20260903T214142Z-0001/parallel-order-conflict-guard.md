# Spec: Parallel Order Conflict Guard

## Goal

当能力图把同一层模块声明为无依赖、却用 `Build order` 明确给出模块间的串行顺序时，
`parallel-safety-gate` 必须把该候选组降级为 `needs-review`，而不是输出
`manual-parallel-eligible`。

## Scope

- 将 capability-map 解析出的显式串行顺序作为 safety gate 的保守审查输入。
- 为每一组受影响模块输出可解释的 order-conflict 证据。
- 保持无矛盾候选组、边界缺失和已有路径/接口冲突分类的行为不变。

## Non-goals

- 不改变 `parallel-readiness` 的候选分层。
- 不创建、管理或回收 worktree、子代理、分支、Issue 或 PR。
- 不将 `Build order` 当作隐式依赖的自动修复依据。

## Acceptance criteria

1. `alpha` 与 `beta` 均无依赖，且 Build order 写为 `alpha → beta` 时，安全门结果是
   `needs-review`，并包含 `build-order-conflict` 证据和两个 module id。
2. 无矛盾的同层模块保留 `manual-parallel-eligible`。
3. 现有 safety gate 回归和全量校验通过。

## Parallel Boundary

```json
{"paths":["plugins/spec-guard/hooks/parallel_safety_gate.py","plugins/spec-guard/hooks/parallel-readiness.py","plugins/spec-guard/hooks/test-parallel-safety-gate.sh"],"publicInterfaces":[],"migrations":[],"globalConfig":[],"testResources":[]}
```
