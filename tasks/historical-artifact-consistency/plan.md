# Plan: historical-artifact-consistency

## Scope

本地实施；tracker 尚未激活。任务范围来自已确认设计，远端 Issue 索引尚不存在。

## 实现顺序与验证

1. 增加历史三分类只读 helper，覆盖合法历史、无快照、孤儿与篡改。
2. 接入 verify；保留无活跃图兼容。
3. 本地 lifecycle 使用图中产物集合保存与恢复，失败时不得丢失证据。

## Checkpoint

已完成：设计、实现、聚焦回归和五项规定检查。结果见 `docs/research/2026-09-06-local-workflow-implementation.md` 及验证 JSON。当前停在本地可审阅状态，无需重复确认已完成动作。下一步是审阅分支差异；没有排队的远端或安装操作。若进入发布/安装，先展示具体版本和命令，再另获授权。自动并行 initiative 保持暂停。
