---
description: 把评审通过的能力图落成当前 tracker 的任务结构
---
立即读取 `.agent/state.json` 的 `tracker`，并**加载对应 bridge skill 后完整执行其「操作一：sync-map」**：

- `github`：`spec-github-bridge`
- `gitlab`：`spec-gitlab-bridge`
- `none`：明确说明不会创建远端 Issue 后停止。

不要只复述路由规则或静默结束。远端写入前，先列出将创建或更新的 Issue；尚未获得用户确认时，明确请求确认后再写入。已获确认时按 bridge 的幂等和逐条 state 写回规则执行，并报告结果。

通用前置：
- spec/CAPABILITY-MAP.md 存在且评审记录已勾选
- tracker 专属的创建、刷新、状态写回与幂等规则只由所选 bridge 定义。
