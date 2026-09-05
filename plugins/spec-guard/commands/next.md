---
description: 从当前 tracker 取下一个可执行任务并开始实现
allowed-tools: Bash, Read, Write
---
先检查当前分支。若它是 `spec-guard/<worker-id>`，这是 controller-owned worker checkout：先用
`parallel-worktree.py verify` 复验 manifest，并从 manifest 读取唯一 `moduleId`；验证失败立即停止。
验证成功也**不得继续执行下面的 canonical `/next` 路由**：共享 `.agent/state.json` 只有一个
`activeModule`，worker 不得修改它、关闭 initiative 或选择其他 module。向用户报告该 worker 的
moduleId，说明实验写流程暂停，保存成果并只读核对；不要继续领取、汇合或回收。

普通分支才执行以下既有流程：

立即读取 `.agent/state.json` 的 `tracker`，加载对应 bridge skill，并完整执行其「操作三：next」：`github` 使用 `spec-github-bridge`，`gitlab` 使用 `spec-gitlab-bridge`，`none` 使用本地任务流程。不要只复述路由规则或静默结束。
取到任务后接 /build。

- **留在当前的模块分支上**，取到新 task 不要另开分支、不要开 PR ——
  交付粒度是模块，`/spec-guard:deliver` 在整个模块跑完后开一次 PR
- 当前模块无可执行任务时：先 `/spec-guard:deliver` 收口，PR 合并后再按 build order
  推进 activeModule 并告知用户
- 所有模块完成时，关闭 Epic issue 并报告
