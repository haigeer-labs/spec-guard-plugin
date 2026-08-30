# Codex 支持模式设计

## 目标

在不改变 Claude Code 已发布接口和行为的前提下，让 spec-guard 在 Codex 中提供与
Claude Code 相同的功能语义：自动状态注入、约定落地和迁移、状态查看、产物校验、
GitHub 同步与任务推进。

“相同”指同一输入项目状态得到同一份状态判定、文件副作用和 GitHub 操作；不要求
两个宿主使用相同的命令名称或安装命令。

## 非目标

- 不 fork 或重写 `addyosmani/agent-skills`。
- 不将 Codex 的宿主判断散落进状态机、digest 或校验逻辑。
- 不自动改写用户已有的 `AGENTS.md` 或 `CLAUDE.md` 标记块以外的内容。
- 不承诺 Codex 在没有等价 agent-skills 工作流依赖时提供 `/spec`、`/plan` 本体。

## 前置依赖

spec-guard 是 agent-skills 的补充；它不提供 spec 与 plan 的上游工作流。Codex
安装前检查必须确认存在已适配 Codex 的 agent-skills 能力。缺失时只报告缺失依赖，
不假装已经启用完整链路，也不创建半套状态文件。

## 架构

```text
                 Claude Code                    Codex
              .claude-plugin/              .codex-plugin/
              commands/*.md                 skills/*-ops/
              hooks/hooks.json              hooks/hooks.json
                    |                             |
                    +-------- 宿主适配器 ----------+
                                      |
                    共享核心：状态机、setup、verify、digest、state.json
                                      |
                     共享的 spec/、tasks/、.agent/state.json 与 GitHub
```

### 共享核心

下列文件和协议维持单一实现：

- `phase-guard.sh`、`verify-artifacts.sh`、`spec-digest.py` 的业务判据；
- `setup-convention.sh`、`teardown-convention.sh` 的迁移、幂等和不覆盖规则；
- `.agent/state.json` 的字段、digest 归一化和退出码；
- GitHub Issue 的创建、依赖和增量写回语义。

特别是 digest 不得按宿主复制或重写，避免产生无法关闭的假警报。

### 宿主适配器

适配器只负责：定位插件根目录、注册 hook、把显式操作暴露为宿主可调用入口，以及
选择项目说明文件。它们不拥有任何状态判据。

| 责任 | Claude Code | Codex |
|---|---|---|
| 清单 | `.claude-plugin/plugin.json` | `.codex-plugin/plugin.json` |
| 自动注入 | 现有 `hooks/hooks.json` | Codex `hooks/hooks.json` |
| 插件根 | `CLAUDE_PLUGIN_ROOT` | `PLUGIN_ROOT`，兼容 `CLAUDE_PLUGIN_ROOT` |
| 项目说明 | 带标记块的 `CLAUDE.md` | 带独立标记块的 `AGENTS.md` |
| 显式入口 | 现有 slash commands | `spec-guard` 操作 skill |

Codex 支持 `UserPromptSubmit`，且插件 hook 同时提供 `PLUGIN_ROOT` 和
`CLAUDE_PLUGIN_ROOT`。因此自动状态注入应先复用现有 `phase-guard.sh`，只新增
Codex 的清单与 hook 注册，不复制脚本。

## 项目约定落地

将 setup/teardown 内的“说明文件”收敛为一个内部宿主策略：

- Claude 目标为 `CLAUDE.md`，沿用既有标记；
- Codex 目标为 `AGENTS.md`，使用新的 Codex 专用完整标记；
- 两端默认追加，已有完整标记块时跳过；`--replace` 仅改块内；teardown 仅删块内；
- `--migrate`、`--dry-run`、目标不覆盖、旧链接只报告等文件操作完全共享；
- 在同一项目启用两个宿主时，两个标记块可以并存，但只能共用一份
  `.agent/state.json`。

新增或抽取该策略前，必须先以当前 Claude 测试固定既有输出和副作用；对 Claude
不改变任何默认参数、文件目标或用户可见命令。

## Codex 操作体验

Codex 端以一个明确的操作 skill 暴露 setup、phase、verify、sync、next、deliver 和
teardown，而非假定 Claude slash commands 可被加载。每个操作调用同一份脚本或
`spec-github-bridge` 工作流，并在输出中说明实际执行的共享语义。

## 验证与发布门禁

每项功能必须有共享 fixture 和两套宿主入口测试：

| 能力 | 共享断言 | Claude 入口 | Codex 入口 |
|---|---|---|---|
| 自动状态注入 | JSON 形状、阶段、断链文案、静默降级 | Claude hook | Codex hook |
| setup / migrate | 文件副作用、dry-run、冲突不覆盖 | command | operation skill |
| teardown | 标记外内容不变、state 保留策略 | command | operation skill |
| verify | failures、warnings、退出码 | command | operation skill |
| GitHub 同步 / next | `gh` 调用记录、state 增量写回 | bridge skill | bridge skill |

发布 CI 的规则：

1. 现有 `validate.sh`、phase-guard 与 verify-artifacts 测试必须继续全绿；
2. 新增 Codex 适配器测试不得以“未运行”伪装通过，需区分通过、失败、环境未就绪；
3. 任何公共协议改动必须同时更新 Claude 与 Codex 的正反用例；
4. 任何仅修改一侧适配器的提交，能力矩阵检查必须确认另一侧无需变化；
5. 真实宿主安装后的 smoke test 是发布前条件，Codex hook 因信任审核未执行时应明确失败。

## 分阶段实施

1. 固定 Claude 现有行为：补齐适配器级契约测试，不移动共享脚本。
2. 增加 Codex 清单和 hook，验证 `UserPromptSubmit` 对现有 `phase-guard.sh` 的零复制复用。
3. 抽取 setup/teardown 的说明文件策略，并先通过完整 Claude 回归。
4. 增加 Codex 的 `AGENTS.md` 约定块和操作 skill，覆盖 setup、迁移、phase、verify、
   sync、next、deliver、teardown。
5. 接入双宿主能力矩阵与真实安装 smoke test，随后才声明 Codex 为受支持宿主。

## 风险与处置

- 上游 agent-skills 无 Codex 等价能力：停止在依赖检查阶段，不发布“完整支持”声明。
- Codex hook 未被用户信任：给出可操作的信任指引；测试将其视为未运行，不计通过。
- `AGENTS.md` 已有用户内容：只操作完整标记块，缺失标记时绝不覆盖。
- 宿主功能漂移：由共享 fixture、矩阵门禁和双端 smoke test 阻止发布。
