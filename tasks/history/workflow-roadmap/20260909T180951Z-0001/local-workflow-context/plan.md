# Plan: local-workflow-context

## Scope

本地实施；tracker 尚未激活。任务范围来自已确认设计，远端 Issue 索引尚不存在。

## 实现顺序与验证

1. 复用共享只读判据与既有正反测试。
2. 增加 setup-convention 显式本地上下文写入，预览、幂等及原子性验证。
3. GitLab 直接入口在认证前拒绝本地阶段；验证旧流程门禁。

## Checkpoint

已完成：设计、实现、聚焦回归和五项规定检查。结果见 `docs/research/2026-09-06-local-workflow-implementation.md` 及验证 JSON。当前停在本地可审阅状态，无需重复确认已完成动作。下一步是审阅分支差异；没有排队的远端或安装操作。若进入发布/安装，先展示具体版本和命令，再另获授权。自动并行 initiative 保持暂停。
