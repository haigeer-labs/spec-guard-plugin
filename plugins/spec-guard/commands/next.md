---
description: 从当前 tracker 取下一个可执行任务并开始实现
allowed-tools: Bash, Read, Write
---

阶段交接、确认或停止前，读取并遵循[共享检查点规则](../references/workflow-checkpoints.md)；按实际路径预告下一步，已有授权不重复询问。

先检查 state 的 `workflowStage`：字段存在时停止取任务，说明当前为本地验证或未知阶段；
不得自动清除字段、创建 tracker 映射或建议用绑定绕过。先按当前 plan 展示成果及下一步。

若 `.agent/state.json` 的 `tracker` 是 `github` 或 `gitlab`，在加载 bridge、选择、认领或写入任何任务前，先运行：

```bash
python3 plugins/spec-guard/hooks/workspace_binding.py inspect --project . --format json
```

只有 JSON 的 `code` 为 `ok` 才能继续。`context-unknown`、`context-mismatch`、
`dependency-blocked` 或 `task-in-progress` 必须立即停止并原样说明；缺失 binding 的旧串行项目引导用户执行
`/spec-guard:bind-workspace`，不得由 `/next` 自动 enrol 或改写 `activeModule`。

立即读取 `.agent/state.json` 的 `tracker`，加载对应 bridge skill，并完整执行其「操作三：next」：`github` 使用 `spec-github-bridge`，`gitlab` 使用 `spec-gitlab-bridge`，`none` 使用本地任务流程。不要只复述路由规则或静默结束。
取到任务后接 /build。

- **留在当前的模块分支上**，取到新 task 不要另开分支、不要开 PR ——
  交付粒度是模块，`/spec-guard:deliver` 在整个模块跑完后开一次 PR
- 当前模块无可执行任务时：先 `/spec-guard:deliver` 收口，PR 合并后再按 build order
  推进 activeModule 并告知用户
- 所有模块完成时，关闭 Epic issue 并报告
