---
description: 从 GitHub 取下一个可执行任务并开始实现
---
Invoke the spec-github-bridge skill，执行「操作三：取下一个任务」，
取到后接 /build。

- 当前模块无可执行任务时，按 build order 推进 activeModule 并告知用户
- 所有模块完成时，关闭 Epic issue 并报告
