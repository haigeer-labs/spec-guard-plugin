---
description: 把评审通过的能力图落成 GitHub Issue 结构
---
Invoke the spec-github-bridge skill，执行「操作一：能力图落库」。

前置：
- spec/CAPABILITY-MAP.md 存在且评审记录已勾选
- 若 .agent/state.json 的 initiative.issue 已有值，停下来问用户是新建还是补充，不要覆盖
- **每建成一个 issue 就立刻写回 .agent/state.json**（Epic → `initiative.issue`，
  每个模块 → `modules.<id>.issue`）。这一步在 GitHub 上做不可逆写入且会中途失败；
  攒到最后写的话，失败一次就留下「GitHub 建了一半 / state.json 全空」，
  而上面那条判据读的正是 state.json —— 重跑会从头再建一套
- 重跑时：`initiative.issue` 有值就跳过建 Epic，`modules.<id>.issue` 有值
  就跳过该模块，只补没建成的
