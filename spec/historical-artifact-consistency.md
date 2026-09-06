# Spec: historical-artifact-consistency

## Objective

历史产物归属与本地阶段完整快照。以 `docs/research/2026-09-06-local-stage-artifacts-checkpoints-design.md` 的对应设计与验收矩阵为契约。

## Commands

`/bin/bash scripts/validate.sh`；`/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh`；`/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh`。聚焦 Python 测试使用 `python3 -B`。

## Structure and Style

实现位于 plugins/spec-guard/hooks、commands、skills、templates；Python 标准库、Bash 3.2；复用现有解析器，探测器只读。

## Testing and Success Criteria

- 增加历史三分类只读 helper，覆盖合法历史、无快照、孤儿与篡改。
- 接入 verify；保留无活跃图兼容。
- 本地 lifecycle 使用图中产物集合保存与恢复，失败时不得丢失证据。

## Boundaries

只实施已确认本地范围；不得创建远端 Issue/PR、发布、修改缓存或恢复并行 initiative。保留全部既有历史产物。不建立 todo.md 或假 Issue 映射。
