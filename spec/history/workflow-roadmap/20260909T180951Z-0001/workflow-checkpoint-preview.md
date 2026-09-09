# Spec: workflow-checkpoint-preview

## Objective

共享检查点预告与入口接入。以 `docs/research/2026-09-06-local-stage-artifacts-checkpoints-design.md` 的对应设计与验收矩阵为契约。

## Commands

`/bin/bash scripts/validate.sh`；`/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh`；`/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh`。聚焦 Python 测试使用 `python3 -B`。

## Structure and Style

实现位于 plugins/spec-guard/hooks、commands、skills、templates；Python 标准库、Bash 3.2；复用现有解析器，探测器只读。

## Testing and Success Criteria

- 新增唯一共享检查点规则，接入两个 bridge、ops、命令与模板。
- 覆盖七类场景、已授权续接、取消和未知结果。
- 运行五项规定检查、聚焦测试与实际历史夹具；记录宿主/安装未验证。

## Boundaries

只实施已确认本地范围；不得创建远端 Issue/PR、发布、修改缓存或恢复并行 initiative。保留全部既有历史产物。不建立 todo.md 或假 Issue 映射。
