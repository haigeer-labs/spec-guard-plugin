---
description: 从当前 tracker 取下一个可执行任务并开始实现
---
读取 `.agent/state.json.tracker` 后路由：`github` 调用 `spec-github-bridge`；`gitlab` 调用 `spec-gitlab-bridge`；`none` 使用本地任务流程。
取到后接 /build。

- **留在当前的模块分支上**，取到新 task 不要另开分支、不要开 PR ——
  交付粒度是模块，`/spec-guard:deliver` 在整个模块跑完后开一次 PR
- 当前模块无可执行任务时：先 `/spec-guard:deliver` 收口，PR 合并后再按 build order
  推进 activeModule 并告知用户
- 所有模块完成时，关闭 Epic issue 并报告
