# 维护者工作流

本文件承接 `CLAUDE.md` 的按需细节，避免每次开发都加载评测历史和低频操作。

## 变更前

先阅读 [设计](design.md) 与 [审查透镜](lenses.md)。前者定义产品边界，后者记录本仓库
反复出现的假断链、空断言与交接失败模式。

作者仓库同时用 spec-guard 管理自身开发（见 `CLAUDE.md`），这里的 hook 输出反映本仓库
initiative 状态，且来自已安装版插件，不是产品回归。用临时 Git 项目验证真实行为。

## 验证矩阵

每次改动先运行：

```bash
/bin/bash scripts/validate.sh
```

下列改动还必须运行相应聚焦检查：

| 改动范围 | 必跑检查 |
| --- | --- |
| `phase-guard.sh` 或激活/阶段逻辑 | `test-phase-guard.sh` 与 `test-verify-artifacts.sh` |
| `verify-artifacts.sh` 或共享判据 | `test-verify-artifacts.sh` 与 `test-phase-guard.sh` |
| Codex adapter、manifest 或 hook 注册 | `test-codex-adapter.sh` 与 `evals/codex-plugin-smoke.sh --selftest` |
| GitLab 路由或 tracker 解析 | `test-gitlab-tracker-integrity.sh --selftest` 与相关 hook 测试 |
| `check-*.py` | `scripts/test-checkers.sh`，每条新判据都有一正一反用例 |
| `spec-digest.py` | 其 self-test、phase 与 verify 两侧回归 |

macOS 上必须用 `/bin/bash`，以覆盖系统自带 bash 3.2；不要让 Homebrew bash 掩盖兼容问题。

## 可选但高价值的检查

```bash
python3 scripts/mutation-check.py
python3 scripts/mutation-check.py --only 归档
/bin/bash evals/skill-deferral.sh --scaffold-only
/bin/bash evals/module-namespace.sh --scaffold-only
/bin/bash evals/next-redo.sh --selftest
/bin/bash evals/sync-map.sh --selftest
```

变异测试会在工作区短暂改写目标文件。它要求目标相对 HEAD 干净，并使用锁防止并发；运行时
不要同时测试、编辑或提交。`skill-deferral`、`module-namespace`、`next-redo` 和 `sync-map`
的非 self-test 模式会调用真实宿主或外部服务，不能把“环境未就绪”误报为产品失败。

## Codex 本地安装与真实 smoke

插件管理器安装的是 marketplace 解析出的副本，不会自动读取当前 Git 工作区。先查看实际来源：

```bash
codex plugin marketplace list
codex plugin list --json
```

第一次从本地源码安装的标准流程是：

```bash
codex plugin marketplace add /absolute/path/to/spec-guard-plugin
codex plugin add spec-guard@spec-guard-marketplace
```

若 `spec-guard-marketplace` 已指向一个发布版，不要在活跃会话中替换它来测试开发源码；应在
隔离的 Codex 配置/机器中安装候选，或先明确备份并恢复原 marketplace。安装或升级后开启新会话，
在 `/hooks` 审核并信任 `UserPromptSubmit`，再运行：

```bash
/bin/bash evals/codex-plugin-smoke.sh \
  --plugin-id spec-guard@spec-guard-marketplace \
  --expected-source /absolute/path/to/spec-guard-plugin/plugins/spec-guard
```

退出码：`0` 为真实 hook 通过，`1` 为已执行的行为失败，`2` 为安装、登录、信任或来源不匹配，
即环境未就绪。

## 提交前

可安装预推送 hook：

```bash
/bin/bash scripts/install-git-hooks.sh
```

提交前检查改动只包含当前目标、没有密钥，并运行与改动面对应的验证。不要把不相关重构、版本发布
或消费者项目状态塞进同一个维护提交。
