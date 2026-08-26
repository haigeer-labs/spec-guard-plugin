---
description: 校验已落地的产物是否符合约定（spec 命名、plan 形态、issue 结构）
allowed-tools: Bash
---

跑一次产物落地校验：

```bash
CLAUDE_PROJECT_DIR=$(pwd) bash "${CLAUDE_PLUGIN_ROOT}/hooks/verify-artifacts.sh"
```

脚本输出已经是给人看的格式，**原样转述**，然后：

- **有 ❌** —— 逐条说明「为什么这是问题」和「怎么改」，**得到确认后再动手**。
  断链和违规都可能是用户故意的，不要自作主张补齐。
- **有 ⚠️** —— 提一句即可，不必追着修。
- **⏭ 不等于通过** —— `gh` 不可用或未认证时 GitHub 层整段跳过，
  要明确告诉用户「这部分没验，不是验过了」。
- **退出码 2** —— 项目没启用约定，提示跑 `/setup-convention`。

## 和 `/phase` 的分工

| | `/phase` | `/verify-artifacts` |
|---|---|---|
| 问题 | 现在在哪个阶段、链路断没断 | 已经落下的产物对不对 |
| 时机 | 每次发言前自动注入（hook） | 按需跑 |
| 成本 | <1s，不读文件内容 | 读文件、打 gh |

三项检查两边都有（根目录 `SPEC*.md` / `todo.md` 并存 / 分支 issue 号），
是刻意的——一个随时提醒，一个按需体检。

## 什么时候该跑

- `/sync-map` 之后：确认 issue 结构和能力图对得上
- `/planning` 之后：确认 task 落进了 issue 而不是 todo.md
- `/deliver` 之前：确认 PR 会带上 `Closes #n`
- 接手别人的分支、或隔了几天回来时
