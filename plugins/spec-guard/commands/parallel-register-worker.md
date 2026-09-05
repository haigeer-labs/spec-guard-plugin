---
description: 经确认后登记用户已创建的 Desktop worktree worker
argument-hint: "<run-id> <module-id> --host <codex-desktop|claude-desktop> --host-worker-id <id> --cwd <absolute-path>"
allowed-tools: Bash, Read, Write
---

这是 register-only 入口。它不创建、隐藏、归档或删除 Desktop session/worktree；**没有本次明确确认时
绝不写 lease 或 host manifest。**

先从用户提供的实际 cwd 展示 run、module、host、稳定 host worker ID 与 Git 身份。`--host` 只能是
`codex-desktop` 或 `claude-desktop`；`--host-worker-id` 不能用标题、pending client ID 或推测值代替。

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# 将 $ARGUMENTS 逐项映射到 RUN、MODULE、HOST、HOST_WORKER_ID、CWD；任一缺失立即停止。
git -C "$CWD" rev-parse --show-toplevel --git-common-dir HEAD
git -C "$CWD" branch --show-current
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-execution.py" status --project "$PROJECT" --run "$RUN" --format json
```

只有用户明确确认上述同一个 run/module/host/cwd 后，才调用登记器：

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-desktop-register.py" register \
  --project "$PROJECT" --run "$RUN" --module "$MODULE" --host "$HOST" \
  --host-worker-id "$HOST_WORKER_ID" --cwd "$CWD" --format json
```

登记失败或 `unknown` 时只报告手工步骤，不能改用 controller worktree、重试领取或创建 Desktop 任务。
成功的 owner=host worker 由宿主可回收；Spec Guard 只记录状态，不获得删除权。
