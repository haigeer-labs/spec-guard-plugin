---
description: 当前模块交付到当前 tracker
allowed-tools: Bash, Read, Write
---

阶段交接、确认或停止前，读取并遵循[共享检查点规则](../references/workflow-checkpoints.md)；按实际路径预告下一步，已有授权不重复询问。

先检查 state 的 `workflowStage`：字段存在时停止交付，说明当前为本地验证或未知阶段；
不得自动清除字段、创建 tracker 映射或建议用绑定绕过。先按当前 plan 展示成果及下一步。

若 `.agent/state.json` 的 `tracker` 是 `github` 或 `gitlab`，在创建、更新、关闭或合并任何远端对象前，先运行：

```bash
python3 plugins/spec-guard/hooks/workspace_binding.py inspect --project . --format json
```

只有 `code=ok` 可继续。任何其他结构化结果都必须停止交付；向用户说明修复方式，缺失 binding 时指向
`/spec-guard:bind-workspace`，但不得在 `/deliver` 自动创建、修复或替换 binding。

交付粒度是**模块**，不是单个 task。模块完成校验、默认分支解析与远端交付命令由所选 bridge 定义；不要在此处调用另一 tracker 的 CLI。

交付前 invoke code-review-and-quality 做五轴自查；有 Critical 级别发现时不要交付，先修。

通过后立即读取 `.agent/state.json` 的 `tracker`，加载对应 bridge skill，并完整执行其「操作四：deliver」：GitHub 使用 `spec-github-bridge`，GitLab 使用 `spec-gitlab-bridge`，本地项目不调用远端交付命令。不要只复述路由规则或静默结束；创建或合并远端 PR/MR 前仍必须取得用户确认。
