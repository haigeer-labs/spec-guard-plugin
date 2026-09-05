---
description: 并行成果汇合已暂停，保留旧资源并提供只读指引
allowed-tools: Bash, Read
---

并行成果汇合的实验性写操作已暂停，返回 `PARALLEL_WRITES_DISABLED`。既有确认参数不能重新开启。

执行以下拒绝入口，并说明原因：

```bash
python3 - "${CLAUDE_PLUGIN_ROOT}/hooks" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
from parallel_execution_lib import ParallelWritesDisabled, reject_parallel_write
try:
    reject_parallel_write()
except ParallelWritesDisabled as error:
    print(json.dumps({"ok": False, "code": error.code, "message": str(error)}, ensure_ascii=False))
    raise SystemExit(1)
PY
```

有 run ID 时使用 /spec-guard:parallel-status 查看旧记录；只需分析候选时使用
/spec-guard:parallel-readiness、/spec-guard:parallel-safety-gate 或 /spec-guard:parallel-guidance。

保留已有代码、分支、worktree 与账本，不重新领取、启动、登记、汇合或回收，也不要编写替代脚本绕过暂停。
旧进程退出成功、旧领取记录或 `owner=host` 都不能证明任务已验收或资源可回收。
升级不会停止已运行的进程；先保存成果并核实宿主任务状态，由用户决定停止或重启。
