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

> Tasks tracked in GitHub Issues #6.

### Phase 1: Schema and read-only validation

- #11 建立账本 schema 与事件状态机

- #12 实现 checkpoint 查询与完整性验证（blocked by #11）

### Checkpoint: Read-only contract

- #13 全部账本 schema 与完整性正反用例通过；读取任何损坏账本都不产生“通过”结果。（blocked by #12）


### Phase 2: Safe append API

- #14 实现原子创建与事件追加（blocked by #13）

- #15 接入仓库校验门禁（blocked by #14）

### Checkpoint: Ledger complete

- #16 账本创建、查询、追加、完整性验证和中断保护均通过；既有 phase、verify 与 Codex adapter 回归保持通过。（blocked by #15）


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
