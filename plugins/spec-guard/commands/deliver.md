---
description: 当前模块交付到当前 tracker
allowed-tools: Bash, Read, Write
---
交付粒度是**模块**，不是单个 task。模块完成校验、默认分支解析与远端交付命令由所选 bridge 定义；不要在此处调用另一 tracker 的 CLI。

交付前 invoke code-review-and-quality 做五轴自查；有 Critical 级别发现时不要交付，先修。

通过后立即读取 `.agent/state.json` 的 `tracker`，加载对应 bridge skill，并完整执行其「操作四：deliver」：GitHub 使用 `spec-github-bridge`，GitLab 使用 `spec-gitlab-bridge`，本地项目不调用远端交付命令。不要只复述路由规则或静默结束；创建或合并远端 PR/MR 前仍必须取得用户确认。
