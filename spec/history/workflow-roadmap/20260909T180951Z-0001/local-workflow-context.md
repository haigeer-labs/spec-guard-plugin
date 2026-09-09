# Spec: local-workflow-context

## Objective

显式本地上下文、共享阶段判据与 tracker 门禁。以 `docs/research/2026-09-06-local-stage-artifacts-checkpoints-design.md` 的对应设计与验收矩阵为契约。

## Commands

`/bin/bash scripts/validate.sh`；`/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh`；`/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh`。聚焦 Python 测试使用 `python3 -B`。

## Structure and Style

实现位于 plugins/spec-guard/hooks、commands、skills、templates；Python 标准库、Bash 3.2；复用现有解析器，探测器只读。

## Testing and Success Criteria

- 复用共享只读判据与既有正反测试。
- 增加 setup-convention 显式本地上下文写入，预览、幂等及原子性验证。
- GitLab 直接入口在认证前拒绝本地阶段；验证旧流程门禁。

## Boundaries

只实施已确认本地范围；不得创建远端 Issue/PR、发布、修改缓存或恢复并行 initiative。保留全部既有历史产物。不建立 todo.md 或假 Issue 映射。
