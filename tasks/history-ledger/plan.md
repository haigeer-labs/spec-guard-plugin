# Implementation Plan: history-ledger

## Overview

实现唯一的历史账本工具 `capability-history.py`，供后续生命周期、校验与迁移模块共享。
它管理 `spec/CAPABILITY-HISTORY.json` 的 schema、事件追加、checkpoint 查询和证据完整性，
但不执行当前文件的移动或恢复。

## Architecture Decisions

- 历史账本的唯一实现为 Python 3 标准库脚本；Bash 入口和校验器不得各自解析或改写 JSON。
- 事件仅追加；最后事件推导 initiative 状态。`created` 是每个 initiative 的首事件。
- checkpoint ID 使用 `YYYYMMDDTHHMMSSZ-NNNN`；JSON 路径必须是项目根相对且不允许逃逸。
- 文件摘要使用完整 SHA-256；这与现有 `spec-digest.py` 的“当前能力图投影指纹”职责不同，
  两者不合并也不互相复制实现。

## Task List

### Phase 1: Schema and read-only validation

- [ ] Task 1: 建立账本 schema 与事件状态机
  - Acceptance: 能验证 initiative ID、首个 `created` 事件、允许状态转换、模块/路径字段与
    checkpoint ID；非法输入给出非零结果和可读原因。
  - Verify: 新增 self-test，覆盖合法完整生命周期及每种非法转换。
  - Files: `plugins/spec-guard/hooks/capability-history.py`, `plugins/spec-guard/hooks/test-capability-history.sh`

- [ ] Task 2: 实现 checkpoint 查询与完整性验证
  - Acceptance: 可按 `initiative-id/module-id` 查询最新 checkpoint；能发现 map/spec/plan 缺失、
    摘要不一致、绝对路径和目录逃逸。
  - Verify: fixture 覆盖同名模块跨 initiative、`null` 未产生证据、篡改和缺失文件。
  - Files: `plugins/spec-guard/hooks/capability-history.py`, `plugins/spec-guard/hooks/test-capability-history.sh`

### Checkpoint: Read-only contract

- [ ] 全部账本 schema 与完整性正反用例通过。
- [ ] 读取任何损坏账本都不产生“通过”结果。

### Phase 2: Safe append API

- [ ] Task 3: 实现原子创建与事件追加
  - Acceptance: 可创建账本、追加合法事件；重复 initiative、重复 checkpoint 或中断写入不破坏
    原文件；写后可立即被只读验证。
  - Verify: 模拟写前失败和替换失败，比较原账本字节不变；追加后运行查询用例。
  - Files: `plugins/spec-guard/hooks/capability-history.py`, `plugins/spec-guard/hooks/test-capability-history.sh`

- [ ] Task 4: 接入仓库校验门禁
  - Acceptance: 账本 self-test 被 `scripts/validate.sh` 执行；新脚本符合 Bash 3.2/Python 3
    和现有检查器约束。
  - Verify: `/bin/bash scripts/validate.sh` 通过，且故意损坏 fixture 时测试失败。
  - Files: `scripts/validate.sh`, `plugins/spec-guard/hooks/test-capability-history.sh`

### Checkpoint: Ledger complete

- [ ] 账本创建、查询、追加、完整性验证和中断保护均通过。
- [ ] 既有 phase、verify 与 Codex adapter 回归保持通过。

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| 账本与 Bash 调用方产生不同解析规则 | 所有 JSON 判据集中在一个 Python 工具中。 |
| 事件历史被覆盖 | 只提供 append 操作；验证器拒绝不合法的首事件和状态转换。 |
| 文件写入中断损坏账本 | 写入同目录临时文件，校验后原子替换；失败保留原文件。 |
| 历史路径逃出项目根 | 账本拒绝绝对路径、`..` 逃逸与非预期历史目录。 |

## Out of Scope

- 移动/复制当前 spec、plan 或能力图。
- 设置 `activeModule`、修改 `.agent/state.json`。
- 用户项目迁移、Claude/Codex 命令入口或 `verify-artifacts` 集成。
