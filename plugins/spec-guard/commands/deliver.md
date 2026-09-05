---
description: 当前模块交付到当前 tracker
allowed-tools: Bash, Read, Write
---
先检查当前分支。若它是 `spec-guard/<worker-id>`，这是 controller-owned worker checkout：先用
`parallel-worktree.py verify` 复验 manifest，并从 manifest 读取唯一 `moduleId`；验证失败立即停止。
验证成功也**不得继续执行下面的 canonical `/deliver` 路由**：worker 不得创建模块 PR、推进
`activeModule`、关闭 initiative 或自行 merge。向用户报告该 worker 的 moduleId、分支和待人工
核验状态，说明实验写流程暂停，保存成果并只读核对；不要继续汇合或回收。

普通分支才执行以下既有流程：

交付粒度是**模块**，不是单个 task。模块完成校验、默认分支解析与远端交付命令由所选 bridge 定义；不要在此处调用另一 tracker 的 CLI。

交付前 invoke code-review-and-quality 做五轴自查；有 Critical 级别发现时不要交付，先修。

通过后立即读取 `.agent/state.json` 的 `tracker`，加载对应 bridge skill，并完整执行其「操作四：deliver」：GitHub 使用 `spec-github-bridge`，GitLab 使用 `spec-gitlab-bridge`，本地项目不调用远端交付命令。不要只复述路由规则或静默结束；创建或合并远端 PR/MR 前仍必须取得用户确认。
