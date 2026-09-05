---
description: 显式绑定当前 Git worktree 到一个 Spec Guard tracker 模块
allowed-tools: Bash, Read
---
这是一次本地上下文绑定，不会创建 Agent、worktree、分支、Issue、MR 或并行执行器。
它也不是跨 worktree/machine 的锁。

1. 在当前项目根目录运行以下只读检查，并展示 JSON 中的 `code`、模块和 tracker：

   ```bash
   python3 plugins/spec-guard/hooks/workspace_binding.py inspect --project . --format json
   ```

2. 如果结果是 `ok` 且 `binding.moduleId` 就是用户请求的模块，不写入并报告现有 binding。
   如果是 `context-unknown` 或 `context-mismatch`，解释 `message`；不要由 `/next` 自动修复或 enrol。

3. 第一次绑定时，先从 `.agent/state.json`、`spec/CAPABILITY-MAP.md` 和当前 Git `origin` 确认将写入的 tracker、initiative Issue、moduleId、module Issue、worktree-local `gitDir` 与 canonical repo。仅在用户明确指定模块后执行：

   ```bash
   python3 plugins/spec-guard/hooks/workspace_binding.py bind --project . --module <module-id> --format json
   ```

4. 若已有不同或损坏的 binding，先展示新旧身份差异。只有用户明确确认重新绑定到该模块后，才追加 `--replace`；该操作只替换当前 worktree 自己 Git directory 下的记录：

   ```bash
   python3 plugins/spec-guard/hooks/workspace_binding.py bind --project . --module <module-id> --replace --format json
   ```

5. `dependency-blocked` 表示当前 `HEAD` 未包含直接前置模块 Issue 的关闭证据；不得用手工编辑 JSON 绕过。完成前置模块或切换到具备该历史的 worktree 后重新检查。

不要把 `activeModule` 改为数组。非默认模块只在用户明确绑定的 linked worktree 中可用；后续 `/next`、`/deliver` 的统一门禁由 tracker-integrity 模块后续任务接入。
