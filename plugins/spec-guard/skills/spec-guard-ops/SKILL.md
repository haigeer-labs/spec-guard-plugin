---
name: spec-guard-ops
description: 在 Codex 中运行 Spec Guard 的本地约定、只读验证和文档／历史工具。
---

本 skill 不接管远端 tracker。GitHub/GitLab 的旧任务投影、选择、绑定和交付流程已退役；
不得从 `.agent/state.json` 恢复它们，也不得创建或修改远端对象。

## 解析环境

从当前已启用的插件安装解析根目录，不猜测缓存版本：

```bash
CODEX_PLUGINS="$(codex plugin list --available --json 2>/dev/null || true)"
ROOT="$(printf '%s' "$CODEX_PLUGINS" | python3 -c '
import json, sys
try:
    plugins = json.load(sys.stdin).get("installed", [])
except (TypeError, ValueError):
    plugins = []
for plugin in plugins:
    if plugin.get("name") == "spec-guard" and plugin.get("installed") and plugin.get("enabled"):
        print(plugin["source"]["path"])
        break
')"
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

`ROOT` 为空时停止并说明插件未安装或未启用。

## setup

只安装本地多模块目录约定；先用 `--dry-run` 预览。用户确认后才省略它：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/setup-convention.sh" local --host=codex --dry-run
```

已有声明块要升级时追加 `--replace`。遗留 `.agent/state.json` 是历史记录，不得用
setup 覆盖。

## phase and verify

两者均为只读：

```bash
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/phase-guard.sh"
CLAUDE_PROJECT_DIR="$PROJECT" /bin/bash "$ROOT/hooks/verify-artifacts.sh"
```

phase 若发现旧 remote-tracker state，只报告迁移提示；它不认证、不读取映射，也不选择任务。

## documentation

文档基线、影响和验证仍是显式声明工具，不能扫描代码或 Git 历史来猜测状态：

```bash
python3 -B "$ROOT/hooks/documentation_baseline.py" --project "$PROJECT" --format json
python3 -B "$ROOT/hooks/documentation_impact.py" --project "$PROJECT" --module <module-id> --format json
python3 -B "$ROOT/hooks/documentation_verification.py" --project "$PROJECT" --module <module-id> --format json
```

只有用户确认后才修改基线、模块 Spec 或 Plan。

## history

历史验证与审计均为只读；导入或补正仍须单独确认：

```bash
/bin/bash "$ROOT/hooks/verify-history.sh" "$PROJECT"
python3 "$ROOT/hooks/capability-history.py" audit "$PROJECT/spec/CAPABILITY-HISTORY.json" "$PROJECT"
python3 "$ROOT/hooks/history-migration.py" preview "$PROJECT"
```

历史快照与旧 state 是证据，不是恢复旧 tracker 工作流的授权。
