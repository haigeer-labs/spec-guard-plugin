# Implementation Plan: initiative-lifecycle

## Overview

在不改变当前 `spec/`、`tasks/` 与 `.agent/state.json` 路径契约的前提下，实现 initiative 的
暂停、恢复与终态 checkpoint。账本读写只调用 `capability-history.py`。

## Task List

- [ ] Task 1: 实现 pause 的 dry-run 与失败保护
  - Acceptance: 枚举当前 map/spec/plan 与目标 checkpoint；冲突、缺当前图或账本写入失败时不删除源文件。
  - Verify: `test-initiative-lifecycle.sh` 覆盖 dry-run、冲突与失败回滚。
  - Files: `initiative-lifecycle.sh`, `test-initiative-lifecycle.sh`

- [ ] Task 2: 实现 pause 与终态 checkpoint
  - Acceptance: 成功后历史目录和账本事件完整，当前路径/state 被安全清理；终态类型准确。
  - Verify: A 暂停、完成、放弃、替代的 fixture 回归。
  - Files: `initiative-lifecycle.sh`, `test-initiative-lifecycle.sh`

- [ ] Task 3: 实现 resume
  - Acceptance: 仅最后状态为 paused 的 A 可恢复；B 活跃时先暂停 B；恢复后 state 与当前路径指向 A。
  - Verify: A→B→resume A 和目标冲突/损坏 checkpoint 反向用例。
  - Files: `initiative-lifecycle.sh`, `test-initiative-lifecycle.sh`

- [ ] Task 4: 接入总校验与宿主入口
  - Acceptance: 测试进入 `validate.sh`，Claude/Codex 入口使用相同脚本与确认语义。
  - Verify: `scripts/validate.sh`、hook 回归和 Codex adapter 回归全绿。
  - Files: `scripts/validate.sh`, commands/skills, tests

## Risks

- 文件移动中断：始终先复制、验证、写账本，最后才清理源路径。
- 恢复覆盖当前工作：必须暂停当前 initiative，并要求确认。
- 账本与文件不同步：每个 checkpoint 先用账本工具验证再报告成功。
