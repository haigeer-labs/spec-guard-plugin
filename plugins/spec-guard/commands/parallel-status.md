---
description: 只读汇总旧 run、worker 和进程记录，失败返回非零
argument-hint: "<run-id>"
allowed-tools: Bash, Read
---

这是只读命令。已有 run、worker、分支、worktree 和记录保持不变。

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/parallel-execution.py" status \
  --project "$PROJECT" --run "$ARGUMENTS" --details --format json
```

如实展示汇总结果及退出码；任何记录读取失败或身份无法核验时，总体 ok=false、退出非零。
unknown worker 不可自动处置。claimed 只表示旧领取记录存在，不能证明模块完成。

completed 的原值在 recordedState 中，有效状态为 unverified：旧版进程退出成功，任务验收未核验。
owner=host 表示宿主管理，显示“完成与可回收性未核验”；不套用插件 CLI 的进程记录要求。
缺少 controller process record 不代表宿主任务损坏。

本次查询退出 0 只表示查询成功。实验性写操作暂停；不要依据旧状态继续调用汇合、领取或回收入口。
