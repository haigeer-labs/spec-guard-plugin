---
name: spec-guard-ops
description: 在 Codex 中执行 spec-guard 的约定落地、状态探测、产物校验与清理操作。
---

阶段交接、确认或停止前，读取并遵循[共享检查点规则](../../references/workflow-checkpoints.md)；按实际路径预告下一步，已有授权不重复询问。

## 公共环境

所有确定性脚本操作都从 Codex 已启用插件清单和项目根解析路径：

```bash
CODEX_PLUGINS="$(codex plugin list --available --json 2>/dev/null || true)"
ROOT="$(printf '%s' "$CODEX_PLUGINS" | python3 -c '
import json, sys
try:
    plugins = json.load(sys.stdin).get("installed", [])
except (ValueError, TypeError):
    raise SystemExit
for plugin in plugins:
    if plugin.get("name") == "spec-guard" and plugin.get("installed") and plugin.get("enabled"):
        print(plugin["source"]["path"])
        break
')"
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

若 `ROOT` 为空，停止并说明 spec-guard 未安装或未启用；不要猜测用户目录，也不要假定 hook
环境变量会传递给 agent shell。

## `setup`

在当前项目写入 Codex 约定时，执行：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/setup-convention.sh" github --host=codex
```

用户要求 GitLab tracker 时，将 `github` 改为 `gitlab`；要求本地 tracker 时改为 `local`。需要预览时加 `--dry-run`；已有
Codex 标记而要求升级时加 `--replace`。将脚本输出原样转述，成功后提醒提交 `AGENTS.md`、
`.agent/state.json` 与新建目录。

## `local-context`

用户明确选择已有图/spec/plan 的本地验证阶段时，从同一插件目录调用现有 setup 入口：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/setup-convention.sh" github \
  --local-validation --module=<module-id> --title="<initiative title>"
```

GitLab 使用 `gitlab`。默认只预览 state 前后差异；用户已确认这组标题、模块及本地范围后，
用同样参数加 `--confirm` 写入；`--dry-run` 始终不写。已有授权直接承接，不重复询问。
入口仅写 `.agent/state.json`，不创建图/spec/plan，不做认证或 tracker 操作。普通 setup
继续创建初始空 state；本入口在 plan 就位后补齐上下文。已有远端映射、disabled state、
非法上下文拒绝覆盖。需要切换模块时先确认当前范围已收口，再重读目标模块 spec/plan。

`workflowStage` 存在时，sync/bind/next/deliver 都不可执行。退出本地阶段必须先预告并获准
具体 tracker 激活范围；不能自动删字段消除提示。源码目录与实际加载目录可能不同，
脚本测试成功不代表安装或宿主加载已更新。

## `phase`

只读地查看当前阶段：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/phase-guard.sh"
```

解析结果后说明阶段、事实、断链项和建议下一步；无输出表示项目尚未启用约定，不要创建文件。

`LOCAL_VALIDATION` 表示 state 显式记录了当前本地验证模块，tracker 尚未激活；不等于
空闲、已领取任务或获得执行许可。按当前 plan 的最新检查点说明成果、下一步与下次停点。
`LOCAL_VALIDATION_INVALID` 时核对 state/spec/plan，不自动清字段或激活 tracker。
源码结果和已安装插件结果分别报告，旧版 0.8.0 不支持该状态。

## `roadmap`

按需、只读地展示当前 Initiative 的完整工作流路线。默认只显示当前模块及直接依赖/后继：

```bash
python3 -B "$ROOT/hooks/workflow_roadmap.py" --project "$PROJECT"
```

用户明确要求当前活跃能力图的完整模块矩阵时才追加 `--all`：

```bash
python3 -B "$ROOT/hooks/workflow_roadmap.py" --project "$PROJECT" --all
```

该入口不调用 tracker 写操作、不改 `.agent/state.json`、不绑定 worktree、不领取任务，也不管理
端口、进程或外部数据服务。无法唯一确认 Initiative、能力图、模块、检查点或远端事实时，保留脚本的
`?`/`!` 结论，不按分支名、文件时间或 task 数量猜测。`local-validation` 仅展示本地路线，不能建议
sync/next/deliver。worktree、分支和 detached HEAD 是执行上下文，不构成模块或任务权限。

## `verify`

只读地校验已落产物：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/verify-artifacts.sh"
```

如有违规，说明原因与修复方式，得到用户确认后才改动项目；退出码 2 表示尚未启用约定。

## `verify-history`

历史证据校验为只读操作，调用共享脚本：

```bash
/bin/bash "$ROOT/hooks/verify-history.sh" "$PROJECT"
```

无账本时报告“未验证”；orphan 或篡改证据时报告失败，不自动删除任何文件。

## `audit-history`

语义审计同样是只读的。它会把 checkpoint map 与账本字段逐项比对，并把未被证据
支持的状态和时间报告为 `unknown`，不改动历史产物：

```bash
LEDGER="$PROJECT/spec/CAPABILITY-HISTORY.json"
[ -f "$LEDGER" ] || { echo "未验证：没有 capability history ledger"; exit 0; }
python3 "$ROOT/hooks/capability-history.py" audit "$LEDGER" "$PROJECT"
```

审计发现不授权猜测或覆盖历史值。应先向用户说明每项证据缺口。

## `correct-history`

这是确认门控的写操作。只有用户明确确认本次审计报告与补正内容后，才可以运行：

```bash
python3 "$ROOT/hooks/capability-history.py" correct --confirm \
  "$PROJECT/spec/CAPABILITY-HISTORY.json" "$AUDIT_REPORT" "$CORRECTION"
```

`AUDIT_REPORT` 和 `CORRECTION` 必须由用户审阅；后者须含 audit report 的 SHA-256、
来源、原值、修正值、审计时间以及 `initiativeId`、`eventIndex`、`checkpointId`。
该操作只追加 `history-correction` 事件，绝不重写
checkpoint。没有 `--confirm`、哈希不匹配、证据不充分或把 `unknown` 升级为 `completed`
时停止并不写入。

## `history-migration`

迁移预览是只读操作：

```bash
python3 "$ROOT/hooks/history-migration.py" preview "$PROJECT"
```

执行导入前，必须说明它会创建新的历史 checkpoint 与账本，并取得用户明确确认；确认后才调用：

```bash
python3 "$ROOT/hooks/history-migration.py" import --confirm "$PROJECT"
```

不要自行写入或修改旧 spec、plan、state 与 Git 历史。

## `parallel-readiness`

这是只读的并行开发候选分析：它只根据能力图依赖层和精确的默认分支 SHA 给出
`candidate-only` 组，**不等于安全可并行**，也不会创建 worktree、分支、宿主子任务、
Issue 或更改 `.agent/state.json`、`/next`、生命周期和 hook。

默认使用本地已知的远端跟踪快照（报告会标明新鲜度未验证）：

```bash
python3 "$ROOT/hooks/parallel-readiness.py" --project "$PROJECT"
```

只有用户明确要求最新远端默认分支，且已完成用户确认允许联网刷新后，才追加
`--refresh`：

```bash
python3 "$ROOT/hooks/parallel-readiness.py" --project "$PROJECT" --refresh
```

刷新失败时报告失败；不要回退成“最新”结论。无论哪种结果，都提示用户下一步需由
parallel-safety-gate 审查路径、接口、迁移、配置和测试资源冲突。

## `parallel-safety-gate`

这是显式、只读的安全门；`manual-parallel-eligible` 不会自动创建或回收任何 worktree、
任务、分支、Issue 或子代理，也不改 state、`/next` 或 hook：

```bash
python3 "$ROOT/hooks/parallel-safety-gate.py" --project "$PROJECT"
```

只有用户明确要求并确认联网刷新后才追加 `--refresh`。缺失边界声明或任意冲突必须报告
`needs-review`/`sequential-required`，不得推荐自动并行。

## `parallel-guidance`

只为 `manual-parallel-eligible` 输出人工 worker 命名与汇合清单，不创建、管理或回收
worktree、任务、分支或 Issue：

```bash
python3 "$ROOT/hooks/parallel-guidance.py" --project "$PROJECT"
```

用户明确确认联网刷新后才追加 `--refresh`；其余结果仅说明为何应人工审查或串行。

## `parallel-subagent-preflight`

这是 **Codex 专用的只读预检**，不是并行代码实现。先运行 safety gate：

```bash
python3 "$ROOT/hooks/parallel-safety-gate.py" --project "$PROJECT"
```

只在报告对目标候选组返回 `manual-parallel-eligible`、当前会话提供原生 `spawn_agent`
工具、且用户**明确确认**要开启子智能体预检时，父会话才可以为每个模块调用一次
`spawn_agent`。每个任务名使用 `sg-preflight-<module-id>`，提示首行使用
`SG 自动并行预检｜<module-id>`，并要求子智能体：

- 只读检查模块 spec、`Parallel Boundary`、依赖、实施风险与测试范围；
- 不修改文件，不运行会写入的测试，不提交、不推送；
- 不运行 `git worktree`、`git branch`、`git merge`、`git push`，也不创建 Issue、PR 或改 state；
- 用简短结构化结果报告边界冲突、待澄清项和建议的串行/人工 worktree 下一步。

父会话必须等待全部子智能体并汇总结果，明确说明“通过预检不等于授权并行写入”。
子智能体共享父会话工作目录，不能被描述为隔离 worktree。

若 safety gate 不合格、用户未确认、或原生 `spawn_agent` 工具不可用，停止预检：不模拟
子智能体、不启动独立聊天，报告降级原因并运行既有 `parallel-guidance` 生成用户手动管理的
隔离 worktree 指引。任何 `--refresh` 仍需用户明确确认后才可透传。

## `parallel-execute`

实验性并行执行写操作已暂停，使用下面的统一拒绝入口。

## `parallel-integrate`

实验性并行汇合写操作已暂停，使用下面的统一拒绝入口。

## `parallel-reclaim`

实验性并行回收写操作已暂停，使用下面的统一拒绝入口。

## `parallel-register-worker`

实验性 Desktop 登记写操作已暂停。上述四个写入口统一执行：

```bash
python3 - "$ROOT/hooks" <<'PY'
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

返回 PARALLEL_WRITES_DISABLED，不因旧确认参数、候选组或历史记录重新开放。
保存已有成果、worktree 和账本；不要编写替代脚本、创建宿主任务、重领或清理来绕过暂停。
升级不停止旧会话中的进程，由用户在保存成果和核对任务后决定停止或重启。

## `parallel-status`

只读汇总。RUN 必须取用户明确提供的 run ID，不能从不明记录猜测：

```bash
python3 "$ROOT/hooks/parallel-execution.py" status \
  --project "$PROJECT" --run "$RUN" --details --format json
```

如实展示总体 ok 和退出码，失败不能忽略。旧 completed 显示 unverified 与 recordedState；
claimed 只说明历史领取记录存在。owner=host 显示“完成与可回收性未核验”，不要求插件进程记录。
查询成功不表示任务验收成功；保留旧资源供人工核对。

## `teardown`

这是破坏性操作。先明确告知会删除 `AGENTS.md` 中完整的 Codex 约定块，并要求用户确认。
只有确认后才执行：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/teardown-convention.sh" --host=codex
```

原样转述脚本结果；不要删除标记外内容或手动修改 state。

## `lifecycle`

用户请求暂停、恢复或结束 initiative 时，先说明真实操作会复制或恢复当前
`spec/`、`tasks/` 与 `.agent/state.json`，并明确要求确认。仅在确认后调用共享脚本：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/initiative-lifecycle.sh" <pause|resume|complete|abandon|supersede> --project "$PROJECT" --initiative <id>
```

用户只要求预览时追加 `--dry-run`；不要自行复制、移动或覆盖这些文件。

## `sync-map`

先读取 `.agent/state.json` 的 `tracker`。`github` 加载 `spec-guard:spec-github-bridge`；
新建/补充前，使用公共环境解析出的当前安装包运行严格图校验：

```bash
python3 "$ROOT/hooks/capability-map.py" "$PROJECT/spec/CAPABILITY-MAP.md" || exit "$?"
```

失败或旧安装包缺少脚本时停止，报告升级/修正输入后重试，不自行解析兜底。
创建顺序取严格结果的 `order`，依赖只取 `modules[].dependsOn`；digest 的 `order` 仍是
表格行序。通过校验不代替写入确认；仅刷新旧摘要时按 bridge 原规则保留历史兼容。

`none` 保持本地流程。GitLab 使用确定性入口，默认只预览：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/sync-map-gitlab.sh"
```

原样转述计划。只有用户明确确认将创建的 Issue 后，才追加 `--confirm` 重跑；脚本会逐条创建
Issue 并写回 state。不要再以 bridge prose 模拟 GitLab 同步。

## `next`

如果当前上下文已经表明这是受管 worker（已知 manifest/宿主绑定或 spec-guard worker 分支），
报告实验写流程暂停，先保存成果并只读核对。不得运行无任务绑定的 canonical next/deliver，
不得修改 activeModule 或改领其他模块；完整自动检测与任务绑定属于后续 tracker 整改。

对 `github`/`gitlab`，先运行 `python3 "$ROOT/hooks/workspace_binding.py" inspect --project "$PROJECT" --format json`。
只有 `code=ok` 才按 `tracker` 路由；其他结果只报告并引导用户显式 `/spec-guard:bind-workspace`，不自动 enrol、修复或选择任务。`none` 保持本地流程。

按 `tracker` 路由：`github` 加载 `spec-guard:spec-github-bridge`，`gitlab` 加载
`spec-guard:spec-gitlab-bridge`，`none` 保持本地流程。不要复制或自行改写外部 issue 筛选逻辑。

## `deliver`

已知受管 worker 使用上一节的暂停边界，保留成果和记录，不自动汇合或推进 activeModule。

对 `github`/`gitlab`，先运行 `python3 "$ROOT/hooks/workspace_binding.py" inspect --project "$PROJECT" --format json`。
只有 `code=ok` 可继续交付；任何其他结果都停止远端写入并引导用户显式 `/spec-guard:bind-workspace`，不得自动替换记录。`none` 保持本地流程。

按 `tracker` 路由：`github` 加载 `spec-guard:spec-github-bridge`，`gitlab` 加载
`spec-guard:spec-gitlab-bridge`，`none` 保持本地流程。不要在此 skill 中复制 GitHub、GitLab 或交付流程。
