# Codex 支持模式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 Claude Code 已发布行为的前提下，为 spec-guard 提供等价语义的 Codex 插件模式。

**Architecture:** 保留一份状态机、迁移、校验和 digest 实现；Claude Code 与 Codex 只在插件清单、hook 注册、显式操作入口和项目说明文件选择上分叉。以共享 fixture 加宿主适配器测试防止行为漂移。

**Tech Stack:** Bash 3.2、Python 3、Claude Code plugin manifest、Codex plugin manifest、Codex lifecycle hooks、Markdown skills、GitHub CLI。

---

## 目标文件

| 文件 | 责任 |
|---|---|
| `plugins/spec-guard/.codex-plugin/plugin.json` | Codex 插件清单；声明 skills 与 hooks。 |
| `plugins/spec-guard/hooks/hooks.json` | 保持唯一的 hook 注册内容，供两个宿主加载。 |
| `plugins/spec-guard/templates/codex-block-github.md` | 写入用户项目 `AGENTS.md` 的 GitHub 约定块正文。 |
| `plugins/spec-guard/templates/codex-block-local.md` | 写入用户项目 `AGENTS.md` 的本地模式约定块正文。 |
| `plugins/spec-guard/skills/spec-guard-ops/SKILL.md` | Codex 的 setup、phase、verify、teardown 显式操作入口。 |
| `plugins/spec-guard/hooks/setup-convention.sh` | 选择说明文件/模板；其余迁移、state 与目录逻辑保持共享。 |
| `plugins/spec-guard/hooks/teardown-convention.sh` | 按宿主删除正确的完整标记块。 |
| `plugins/spec-guard/hooks/phase-guard.sh` | 把 `AGENTS.md` 视为已落约定，避免 Codex 误落零足迹分支。 |
| `plugins/spec-guard/hooks/verify-artifacts.sh` | 把 `AGENTS.md` 纳入启用判据与用户指引。 |
| `plugins/spec-guard/hooks/test-phase-guard.sh` | 保留 Claude 回归并新增 Codex 适配器正反断言。 |
| `plugins/spec-guard/hooks/test-verify-artifacts.sh` | 覆盖 `AGENTS.md` 激活和 Claude 不回归。 |
| `plugins/spec-guard/hooks/test-codex-adapter.sh` | 在不调用 Codex 服务的条件下验证 manifest、hook 环境与操作 skill。 |
| `scripts/check-manifests.py`、`scripts/test-checkers.sh`、`scripts/validate.sh` | 校验两个 manifest 的名称/版本/路径和 Codex 适配器测试。 |
| `README.md`、`CHANGELOG.md` | 分别说明支持边界、安装/信任流程和发版记录。 |

### Task 1: 冻结 Claude Code 的现状并建立双清单校验

**Files:**

- Modify: `scripts/check-manifests.py`
- Modify: `scripts/test-checkers.sh`
- Modify: `scripts/validate.sh`
- Modify: `plugins/spec-guard/hooks/test-phase-guard.sh`

- [ ] **Step 1: 为 Codex manifest 写失败测试。**

  在 `scripts/test-checkers.sh` 新增 `mkcodex()`，建立 `.codex-plugin/plugin.json`；分别构造
  `name != spec-guard` 和 `version != Claude manifest version` 的输入。断言校验器非零退出，
  再用相同的 name/version 断言零退出。

  ```bash
  mkcodex "$TMP/codex-bad" wrong-name 0.0.0
  want fail "codex manifest: 名称或版本漂移 → 报错" \
    bash -c "cd '$TMP/codex-bad' && python3 '$ROOT/scripts/check-manifests.py'"
  ```

- [ ] **Step 2: 运行失败测试。**

  Run: `bash scripts/test-checkers.sh`

  Expected: 新的 Codex manifest 用例尚未实现，测试失败。

- [ ] **Step 3: 扩展 `check-manifests.py`。**

  新增一个 `load_manifest(src, host)` 辅助函数；对 marketplace 指向的每个插件读取
  `.claude-plugin/plugin.json`，并在 `.codex-plugin/plugin.json` 存在时验证：

  ```python
  assert codex["name"] == claude["name"]
  assert codex["version"] == claude["version"]
  assert codex["skills"] == "./skills/"
  hooks = codex.get("hooks", "./hooks/hooks.json")
  assert str(hooks).startswith("./")
  ```

  清单不存在在此任务中仍允许，保证本提交前 Claude 校验行为不变；Task 2 创建后再由
  `validate.sh` 要求它存在。

- [ ] **Step 4: 将 Claude 当前行为写成适配器断言。**

  在 `test-phase-guard.sh` 的 `base()` 后新增：含 Claude 约定标题的项目必须没有
  “没有 CLAUDE.md 声明块（零足迹模式）”文本，且仍含“当前阶段”。这是以后改激活判据的
  正向基线，不能只检查“没出 Codex 文案”。

- [ ] **Step 5: 运行共享校验。**

  Run: `/bin/bash scripts/validate.sh && /bin/bash plugins/spec-guard/hooks/test-phase-guard.sh`

  Expected: 现有断言全部通过，新增 Claude 基线通过。

- [ ] **Step 6: 提交。**

  ```bash
  git add scripts/check-manifests.py scripts/test-checkers.sh scripts/validate.sh \
    plugins/spec-guard/hooks/test-phase-guard.sh
  git commit -m "test: 冻结 Claude 适配器契约"
  ```

### Task 2: 增加 Codex 插件清单和无复制 hook 注册

**Files:**

- Create: `plugins/spec-guard/.codex-plugin/plugin.json`
- Create: `plugins/spec-guard/hooks/test-codex-adapter.sh`
- Modify: `scripts/validate.sh`

- [ ] **Step 1: 写 Codex 适配器的失败测试。**

  `test-codex-adapter.sh` 在临时目录中读取 manifest 与 `hooks/hooks.json`，并断言：
  manifest 的 `skills` 为 `./skills/`、hooks 路径为 `./hooks/hooks.json`、hook 事件仅注册
  `UserPromptSubmit`、命令包含 `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}`，以及脚本在只设置
  `PLUGIN_ROOT` 与 `CLAUDE_PROJECT_DIR` 时能输出合法 JSON。

  ```bash
  PLUGIN_ROOT="$PLUG" CLAUDE_PROJECT_DIR="$TMP/project" \
    bash "$PLUG/hooks/phase-guard.sh" | python3 -m json.tool >/dev/null
  ```

- [ ] **Step 2: 运行测试确认失败。**

  Run: `/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh`

  Expected: 因 `.codex-plugin/plugin.json` 不存在而失败。

- [ ] **Step 3: 创建 Codex manifest。**

  ```json
  {
    "name": "spec-guard",
    "version": "0.7.28",
    "description": "多模块 Spec 目录约定、GitHub Issue 打通与链路检测。",
    "skills": "./skills/",
    "hooks": "./hooks/hooks.json"
  }
  ```

  版本必须与 Claude manifest 同步；本任务不变更 `.claude-plugin/`。

- [ ] **Step 4: 让 hook 命令显式优先 Codex 根目录。**

  仅修改 `hooks/hooks.json` 中命令的路径解析前缀：

  ```bash
  ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  SCRIPT="${ROOT}/hooks/phase-guard.sh"
  ```

  继续保留现有 `${CLAUDE_PROJECT_DIR}/.claude/hooks/phase-guard.sh` 回退；失败输出仍必须是
  `UserPromptSubmit` 的合法 JSON，不能使用宿主专属输出形状。

- [ ] **Step 5: 将 Codex 适配器测试纳入 `validate.sh`。**

  在指纹自检之后增加：

  ```bash
  echo "═══ Codex 适配器回归 ═══"
  /bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh || F=1
  ```

- [ ] **Step 6: 运行验证。**

  Run: `/bin/bash scripts/validate.sh && /bin/bash plugins/spec-guard/hooks/test-phase-guard.sh && /bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh`

  Expected: Codex 环境变量模拟通过；Claude 的 110/0 与 verify 的 65/0 仍通过。

- [ ] **Step 7: 提交。**

  ```bash
  git add plugins/spec-guard/.codex-plugin/plugin.json plugins/spec-guard/hooks/hooks.json \
    plugins/spec-guard/hooks/test-codex-adapter.sh scripts/validate.sh
  git commit -m "feat: 增加 Codex hook 插件适配器"
  ```

### Task 3: 将说明文件选择收敛为宿主策略

**Files:**

- Create: `plugins/spec-guard/templates/codex-block-github.md`
- Create: `plugins/spec-guard/templates/codex-block-local.md`
- Modify: `plugins/spec-guard/hooks/setup-convention.sh`
- Modify: `plugins/spec-guard/hooks/teardown-convention.sh`
- Modify: `plugins/spec-guard/hooks/test-phase-guard.sh`

- [ ] **Step 1: 写 setup 的失败用例。**

  在现有 `setup-convention --migrate` 组前增加 `codex_base()`，运行
  `bash "$SETUP" github --host=codex`，断言：`AGENTS.md` 含 Codex 专用完整标记、
  `CLAUDE.md` 不存在、`state.json` 合法。另加 `--replace` 不动标记外文本、
  `--dry-run` 零写入、`local --no-instructions` 退出 2 三个反向用例。

- [ ] **Step 2: 运行失败用例。**

  Run: `/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh`

  Expected: `--host=codex` 尚未识别，Codex 用例失败。

- [ ] **Step 3: 添加只供适配器调用的 `--host`。**

  `setup-convention.sh` 解析 `--host=claude|codex`，默认 `claude`；只允许这两个值。
  在前置检查后定义以下变量，后续所有说明文件读写只能使用它们：

  ```bash
  case "$HOST" in
    claude)
      INSTRUCTIONS="CLAUDE.md"; TEMPLATE_PREFIX="claude-block"
      MARK_B="<!-- BEGIN:agent-skills-convention -->"
      MARK_E="<!-- END:agent-skills-convention -->" ;;
    codex)
      INSTRUCTIONS="AGENTS.md"; TEMPLATE_PREFIX="codex-block"
      MARK_B="<!-- BEGIN:spec-guard-codex-convention -->"
      MARK_E="<!-- END:spec-guard-codex-convention -->" ;;
  esac
  SRC="$TPL/${TEMPLATE_PREFIX}-$( [ "$MODE" = github ] && echo github || echo local ).md"
  ```

  Claude 的两个原有标记必须逐字保留；不能改为带宿主后缀的新标记，否则升级项目会把
  已有声明块识别成未安装并重复追加。

  `--no-claude-md` 保持 Claude 公开兼容；为 Codex 新增等价内部参数
  `--no-instructions`，而非改变旧参数含义。`--host=codex --no-claude-md` 必须退出 2，
  防止用户误以为已启用 Codex 约定。

- [ ] **Step 4: 创建 Codex 模板。**

  两份模板只描述共享路径、tracker 和“操作前加载 skill”；不得出现 Claude slash 命令。
  GitHub 模板必须引用 `spec-guard:spec-github-bridge`，本地模板只给路径与本地计划规则。

- [ ] **Step 5: 将 teardown 按宿主删除。**

  让 teardown 同样解析 `--host=claude|codex`（默认 Claude），并把所有 `CLAUDE.md`
  字面量换成 `${INSTRUCTIONS}`。`--host=codex` 只删除 Codex 标记，不删除 Claude 标记；
  两个宿主都移除后才将 state 改为 `.disabled`。若另一个标记仍存在，保留 state 并输出
  “另一宿主仍启用”的提示。

- [ ] **Step 6: 运行共享与 Claude 回归。**

  Run: `/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh && /bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh`

  Expected: 原 175 条加 Codex setup/teardown 正反断言全部通过；Claude 路径、命令参数和
  文件目标无变化。

- [ ] **Step 7: 提交。**

  ```bash
  git add plugins/spec-guard/templates/codex-block-*.md \
    plugins/spec-guard/hooks/setup-convention.sh plugins/spec-guard/hooks/teardown-convention.sh \
    plugins/spec-guard/hooks/test-phase-guard.sh
  git commit -m "feat: 支持 Codex 项目约定落地"
  ```

### Task 4: 让共享 hook 和校验器识别 Codex 约定

**Files:**

- Modify: `plugins/spec-guard/hooks/phase-guard.sh`
- Modify: `plugins/spec-guard/hooks/verify-artifacts.sh`
- Modify: `plugins/spec-guard/hooks/test-phase-guard.sh`
- Modify: `plugins/spec-guard/hooks/test-verify-artifacts.sh`

- [ ] **Step 1: 为 `AGENTS.md` 激活写失败断言。**

  在 phase 测试中建立只含 `AGENTS.md` Codex 标记、没有 `CLAUDE.md`、没有 state 的项目，
  并断言输出“当前阶段”且不包含“零足迹模式”。在 verify 测试中建立相同项目并断言它不退
  2。另加普通 `AGENTS.md`（无完整标记）仍静默/退 2 的反向断言。

- [ ] **Step 2: 运行失败断言。**

  Run: `/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh && /bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh`

  Expected: 仅 `AGENTS.md` 的正向用例失败。

- [ ] **Step 3: 建立单一激活谓词。**

  在两个脚本中用相同的 shell 片段定义：

  ```bash
  has_claude_block() {
    grep -q "<!-- BEGIN:agent-skills-convention -->" CLAUDE.md 2>/dev/null
  }
  has_codex_block() {
    grep -q "<!-- BEGIN:spec-guard-codex-convention -->" AGENTS.md 2>/dev/null
  }
  HAS_CLAUDE=false; has_claude_block && HAS_CLAUDE=true
  HAS_CODEX=false; has_codex_block && HAS_CODEX=true
  HAS_BLOCK=false
  if [ "$HAS_CLAUDE" = true ] || [ "$HAS_CODEX" = true ]; then HAS_BLOCK=true; fi
  ACTIVE="$HAS_BLOCK"
  [ -f .agent/state.json ] && ACTIVE=true
  ```

  Codex 判据必须检查完整标记而不是标题：普通用户 `AGENTS.md` 也可能出现“Agent Skills”
  字样，不能因此误激活。所有用户文案依据宿主状态改为“项目说明块”，仅在 Claude 入口
  才提 `/setup-convention`。

- [ ] **Step 4: 用 Codex 插件根找 digest。**

  `phase-guard.sh` 与 `verify-artifacts.sh` 的 `SELF_DIR` 初始化改为：

  ```bash
  SELF_DIR="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  ```

  保留 `BASH_SOURCE` 回退。不得新增第二份 digest 实现。

- [ ] **Step 5: 运行完整回归。**

  Run: `/bin/bash scripts/validate.sh && /bin/bash plugins/spec-guard/hooks/test-phase-guard.sh && /bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh`

  Expected: 所有 Claude 反向用例仍通过；Codex 标记是启用信号，普通 AGENTS 文件不是。

- [ ] **Step 6: 提交。**

  ```bash
  git add plugins/spec-guard/hooks/phase-guard.sh plugins/spec-guard/hooks/verify-artifacts.sh \
    plugins/spec-guard/hooks/test-phase-guard.sh plugins/spec-guard/hooks/test-verify-artifacts.sh
  git commit -m "feat: 让共享检查识别 Codex 约定"
  ```

### Task 5: 提供 Codex 的显式操作 skill 与依赖检查

**Files:**

- Create: `plugins/spec-guard/skills/spec-guard-ops/SKILL.md`
- Modify: `plugins/spec-guard/skills/spec-github-bridge/SKILL.md`
- Modify: `plugins/spec-guard/hooks/test-codex-adapter.sh`

- [ ] **Step 1: 写 operation skill 静态失败测试。**

  在 `test-codex-adapter.sh` 读取 `spec-guard-ops/SKILL.md`，断言每项操作均出现一次：
  `setup`、`phase`、`verify`、`teardown`、`sync-map`、`next`、`deliver`；并断言所有脚本
  调用都传 `--host=codex` 且通过 `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}` 定位根。

- [ ] **Step 2: 运行失败测试。**

  Run: `/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh`

  Expected: 缺少 `spec-guard-ops` skill，测试失败。

- [ ] **Step 3: 创建 `spec-guard-ops` skill。**

  skill 的每个确定性操作必须使用以下公共根解析：

  ```bash
  ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  CLAUDE_PROJECT_DIR="$PROJECT" bash "$ROOT/hooks/setup-convention.sh" github --host=codex
  ```

  phase 与 verify 保持只读；teardown 先要求用户确认；sync-map、next、deliver 只委派给
  `spec-github-bridge`，不复制 GitHub 逻辑。

- [ ] **Step 4: 补上 Codex 上游依赖检查。**

  `spec-github-bridge/SKILL.md` 不能再给出 `~/.claude/plugins` 的唯一兜底路径。将 digest
  路径说明改为“优先读取 hook 注入的 `spec-digest:` 事实；无该事实时停止并说明未加载
  spec-guard”，不使用 `find ~/.claude/plugins` 猜版本。这样 Claude 与 Codex 都没有
  宿主硬编码的错误回退。

- [ ] **Step 5: 运行适配器与已有工作流回归。**

  Run: `/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh && /bin/bash scripts/validate.sh`

  Expected: 所有操作都可发现；没有 Codex 已适配 agent-skills 时，skill 明确报告依赖缺失，
  不创建 state 或 issue。

- [ ] **Step 6: 提交。**

  ```bash
  git add plugins/spec-guard/skills/spec-guard-ops/SKILL.md \
    plugins/spec-guard/skills/spec-github-bridge/SKILL.md \
    plugins/spec-guard/hooks/test-codex-adapter.sh
  git commit -m "feat: 增加 Codex 显式操作 skill"
  ```

### Task 6: 发布门禁、文档与真实宿主 smoke test

**Files:**

- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `CLAUDE.md`
- Modify: `scripts/validate.sh`
- Create: `evals/codex-plugin-smoke.sh`

- [ ] **Step 1: 为 smoke 判决器写自检。**

  `evals/codex-plugin-smoke.sh --selftest` 必须包含三类结果：`0=通过`、`1=行为失败`、
  `2=环境未就绪`。分别喂“hook 已执行且输出有效”“hook 未信任/未执行”“输出非法”的记录，
  验证判决器不会将未执行判成通过或产品失败。

- [ ] **Step 2: 运行自检确认失败。**

  Run: `/bin/bash evals/codex-plugin-smoke.sh --selftest`

  Expected: 文件不存在而失败。

- [ ] **Step 3: 实现真实 smoke。**

  脚本只在用户已从本地 marketplace 安装并启用插件后运行：建立最小 Git 仓库，调用 Codex
  非交互模式发送一个 prompt，检查 transcript 或 hook 输出包含“当前阶段”。不能读取到
  已安装插件、hook 未信任、Codex 未登录时统一退出 2，并打印对应修复命令；绝不以空输出
  给出“未加载 skill”的结论。

- [ ] **Step 4: 把免费自检接入 `validate.sh`。**

  ```bash
  /bin/bash evals/codex-plugin-smoke.sh --selftest || F=1
  ```

  真 smoke 不进入 `validate.sh`，因为需要用户安装和 Codex 账户；发布 checklist 必须明确
  运行它并要求退出 0。

- [ ] **Step 5: 更新文档。**

  README 单列“宿主支持矩阵”：Claude 完整支持；Codex 需要已适配的 agent-skills、插件
  hook 信任审核和 `AGENTS.md` 约定。不要声称 Claude slash commands 在 Codex 可用。
  CHANGELOG 写明版本、迁移和限制；CLAUDE.md 的必跑命令新增 Codex adapter 与 smoke 自检。

- [ ] **Step 6: 运行发布验证。**

  Run: `/bin/bash scripts/validate.sh && /bin/bash plugins/spec-guard/hooks/test-phase-guard.sh && /bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh && /bin/bash evals/codex-plugin-smoke.sh --selftest`

  Expected: 全部通过；随后在真实安装的 Codex 新会话运行 `/hooks` 审核并信任 hook，再运行
  `evals/codex-plugin-smoke.sh`，期望退出 0。

- [ ] **Step 7: 提交。**

  ```bash
  git add README.md CHANGELOG.md CLAUDE.md scripts/validate.sh \
    evals/codex-plugin-smoke.sh
  git commit -m "docs: 发布 Codex 支持模式"
  ```

## 交付前检查

- [ ] Claude Code 的原始命令和 `.claude-plugin/` 清单未被重命名或删除。
- [ ] `phase-guard.sh`、`verify-artifacts.sh`、`spec-digest.py` 没有宿主专属业务分支或重复算法。
- [ ] Codex hook 从 `PLUGIN_ROOT` 运行，且只输出官方 `UserPromptSubmit` JSON 形状。
- [ ] 普通 `AGENTS.md` 不会激活插件；仅完整 Codex 标记或 state.json 能激活。
- [ ] Codex hook 未信任、上游依赖缺失、真实 smoke 未运行，均不被报告为“通过”。
- [ ] 真实 Codex 安装 smoke 和全部 Claude 回归均有新鲜通过证据。
