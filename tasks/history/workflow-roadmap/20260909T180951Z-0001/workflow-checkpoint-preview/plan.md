# Plan: workflow-checkpoint-preview

## Scope

本地实施；tracker 尚未激活。任务范围来自已确认设计，远端 Issue 索引尚不存在。

## 实现顺序与验证

1. 新增唯一共享检查点规则，接入两个 bridge、ops、命令与模板。
2. 覆盖七类场景、已授权续接、取消和未知结果。
3. 运行五项规定检查、聚焦测试与实际历史夹具；记录宿主/安装未验证。

## Checkpoint

已完成：设计、实现、聚焦回归和五项规定检查。结果见 `docs/research/2026-09-06-local-workflow-implementation.md` 及验证 JSON。当前停在本地可审阅状态，无需重复确认已完成动作。下一步是审阅分支差异；没有排队的远端或安装操作。若进入发布/安装，先展示具体版本和命令，再另获授权。自动并行 initiative 保持暂停。
