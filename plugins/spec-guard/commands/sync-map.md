---
description: 把评审通过的能力图落成当前 tracker 的任务结构
---
读取 `.agent/state.json.tracker` 后路由：`github` 调用 `spec-github-bridge`；`gitlab` 调用 `spec-gitlab-bridge`；`none` 不创建远端 Issue。

通用前置：
- spec/CAPABILITY-MAP.md 存在且评审记录已勾选
- tracker 专属的创建、刷新、状态写回与幂等规则只由所选 bridge 定义。
