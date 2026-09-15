---
description: 校验已落地的产物是否符合约定（spec 命名、plan 形态、issue 结构）
allowed-tools: Bash
---

阶段交接、确认或停止前，读取并遵循[共享检查点规则](../references/workflow-checkpoints.md)；按实际路径预告下一步，已有授权不重复询问。

跑一次产物落地校验：

```bash
CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" bash "${CLAUDE_PLUGIN_ROOT}/hooks/verify-artifacts.sh"
```

脚本输出已经是给人看的格式，**原样转述**，然后：

- **有 ❌** —— 逐条说明「为什么这是问题」和「怎么改」，**得到确认后再动手**。
  断链和违规都可能是用户故意的，不要自作主张补齐。
- **有 ⚠️** —— 提一句即可，不必追着修。
- **⏭ 不等于通过** —— 远端 CLI 不可用或未认证时对应 tracker 层整段跳过，
  要明确告诉用户「这部分没验，不是验过了」。
- **退出码 2** —— 项目没启用约定，提示跑 `/spec-guard:setup-convention`。

## 和 `/spec-guard:phase` 的分工

| | `/spec-guard:phase` | `/spec-guard:verify-artifacts` |
|---|---|---|
| 问题 | 现在在哪个阶段、链路断没断 | 已经落下的产物对不对 |
| 时机 | 每次发言前自动注入（hook） | 按需跑 |
| 成本 | <1s，不读文件内容 | 读文件、按 tracker 调用远端 CLI |

三项检查两边都有（根目录 `SPEC*.md` / `todo.md` 并存 / 分支归属），
是刻意的——一个随时提醒，一个按需体检。
**重叠项的判定规则必须两边一致**：0.6.0 改模块分支约定时只改了 `phase-guard`，
这边留在 task 分支时代到 0.7.11 —— 模块名带数字就会报假失败。

## 什么时候该跑

- 评审能力图与模块 spec 之后：确认文件名与目录结构一致
- `/plan` 之后：确认任务留在相应模块的本地目录
- 接手别人的分支、或隔了几天回来时
