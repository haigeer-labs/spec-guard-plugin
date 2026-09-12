# CLAUDE.md

给在 **spec-guard 插件源码仓库**工作的 AI agent 使用。

## 作用域与自引用边界

本文件配置的是插件作者仓库，不是给使用者复制到项目中的约定。使用者的模板在
`plugins/spec-guard/templates/claude-block-*.md`，由 `/setup-convention` 写入。

不要在本仓库写入会激活 phase-guard 的声明块，也不要创建活跃的
`.agent/state.json`。两者都会让插件检查自己的源码仓库，产生无意义的自引用状态。
需要验证插件行为时，使用 `evals/codex-plugin-smoke.sh` 建立的临时消费者项目。

## 插件目的

spec-guard 为 `addyosmani/agent-skills` 提供：

1. 多模块 Spec 目录约定；
2. GitHub / GitLab Issue 流程衔接；
3. UserPromptSubmit 链路断裂检测。

改动前先阅读 [docs/design.md](docs/design.md)；已有故障模式和审查方法在
[docs/lenses.md](docs/lenses.md)。

## 核心布局

```
.claude-plugin/marketplace.json         ← marketplace 根清单
plugins/spec-guard/
├── .claude-plugin/plugin.json          ← Claude 清单
├── .codex-plugin/plugin.json           ← Codex 清单（版本必须一致）
├── commands/                            ← slash 命令
├── hooks/                               ← hook、共享脚本与回归测试
├── skills/                              ← tracker / 本地操作技能
└── templates/                           ← 写入消费者项目的模板
docs/design.md                           ← 设计与对象模型
scripts/validate.sh                      ← 仓库完整性校验
```

## 不变量

- hook 默认不生效；无激活信号的无关项目必须静默退出。
- 探测失败必须降级，不能把环境故障说成链路断裂。
- hook 只报告事实和建议，不写文件、不改远端状态。
- `hooks/spec-digest.py` 是唯一指纹算法；不得复制或内联实现。
- `phase-guard.sh` 只能依赖 `bash`、`git` 与 `python3`，不可引入 `jq` 硬依赖。
- 修改共享判据时，同时更新 `phase-guard`、`verify-artifacts` 和两边的正反回归。
- 所有 hook 输出必须是宿主接受的 JSON；不要使用 `cmd | grep -q`，避免 SIGPIPE。
- macOS 兼容性检查必须显式用 `/bin/bash`；变量后接多字节字符时写 `${VAR}`。

## 最小验证

```bash
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
```

按变更范围选择更多检查、真实宿主 smoke、变异测试和预推送 hook；完整规则见
[docs/maintainer-workflow.md](docs/maintainer-workflow.md)。发版与安装副本同步见
[docs/release-process.md](docs/release-process.md)。

## 调试

```bash
CLAUDE_PROJECT_DIR=/path/to/test-project /bin/bash plugins/spec-guard/hooks/phase-guard.sh
CLAUDE_PROJECT_DIR=/path/to/test-project /bin/bash plugins/spec-guard/hooks/phase-guard.sh \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])"
```

无输出只表示两个激活信号都不满足；非零 hook 错误应注入可诊断的 JSON 信息。
