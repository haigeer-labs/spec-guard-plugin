---
description: 把评审通过的能力图落成 GitHub Issue 结构
---
Invoke the spec-github-bridge skill，执行「操作一：能力图落库」。

前置：
- spec/CAPABILITY-MAP.md 存在且评审记录已勾选
- 若 .agent/state.json 的 initiative.issue 已有值，**停下来问用户是新建、
  补充还是刷新**，不要覆盖：
  - 补充 = 能力图新增了模块，只为缺的那几个建 issue
  - 刷新 = 目标段或职责描述改了，一个 issue 都不建，只重写正文的标记块内
- **每建成一个 issue 就立刻写回 .agent/state.json，issue 号和指纹同一次写入**
  （Epic → `initiative.issue` + `initiative.goalDigest`，
  每个模块 → `modules.<id>.issue` + `modules.<id>.rowDigest`）。
  这一步在 GitHub 上做不可逆写入且会中途失败；攒到最后写的话，失败一次就留下
  「GitHub 建了一半 / state.json 全空」，而上面那条判据读的正是 state.json ——
  重跑会从头再建一套
- 指纹一律用 `hooks/spec-digest.py compute` 算，**不要自己实现 sha256**；
  路径见 hook 每轮注入的 `spec-digest:` 那一行
- 刷新时：先 `gh issue edit` 成功，**之后**才写新指纹。顺序反了就等于把分歧
  抹掉，正文永远是旧的而检测再也不报
- 重跑时：`initiative.issue` 有值就跳过建 Epic，`modules.<id>.issue` 有值
  就跳过该模块，只补没建成的
