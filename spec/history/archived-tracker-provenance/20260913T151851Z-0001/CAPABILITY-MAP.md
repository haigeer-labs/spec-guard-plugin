# Capability Map: Archived Tracker Provenance

## 目标

归档 GitHub initiative 时，把 Epic 所属仓库（`owner/repo`）与 Epic 编号一起写进受指纹保护的快照。之后核验归档状态时，只查询归档时记录的原仓库，不再按当前 origin 推断；缺少或无法识别仓库身份时如实报告"未核验"。已有历史不改写，只保证今后的归档可以准确追溯。

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| archive-github-repository | 归档时把 GitHub 仓库身份记入状态快照，归档核验改为只查询快照记录的仓库，缺失时保持未核验 | — |

Build order: archive-github-repository

## 范围约束

- 只处理 GitHub；GitLab 归档核验存在同类问题，本轮不处理。
- 不改写、不补写任何已有 checkpoint 或台账事件，也不新增补正迁移。
- 不新增任务事实源，不改变远端核验需显式 opt-in（`SPEC_GUARD_ARCHIVE_REMOTE_VERIFY=1`）的门禁。

## 评审记录

- [x] 模块边界确认：单一能力，写入与读取两端必须同时交付才有意义，不拆分。
- [x] 依赖单向无环。
- [x] module id 已定稿，spec/plan/tracker 使用同一标识。
- [x] 构建顺序符合依赖拓扑。

评审人：haigeermail（会话内回复"通过"，同时批准模块 spec 与 plan，并授权 sync-map）
日期：2026-09-13
Tracker：GitHub；initiative #15，模块 #16，任务 #17–#19，映射记录于 `.agent/state.json`。
