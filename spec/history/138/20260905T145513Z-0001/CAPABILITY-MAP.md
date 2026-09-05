# Capability Map: Spec Guard 整体审计整改与收尾

## 目标

修复 Spec Guard 现有工作流的一致性与历史真实性问题，封闭尚未可靠的实验性并行写入口，保护已有成果和普通串行流程。以可复现的行为测试、GitHub/GitLab 真实流程及四端分别核验的证据收尾，不扩大为完整自动并行执行器。

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| audit-safety-containment | 封闭危险实验写入口，保留只读诊断、旧资源及人工恢复说明，修正旧记录可信度与身份校验 | — |
| audit-map-consistency | 修复并列 Build order、解析消费者和并行边界判断的一致性，避免旧摘要迁移产生假漂移 | audit-safety-containment |
| audit-tracker-integrity | 修复 GitLab 同步幂等与中断恢复，统一工作区任务绑定和 next/deliver 选择边界 | audit-map-consistency |
| audit-history-integrity | 修复历史职责、依赖、状态及时间的证据来源，保留旧快照并提供可解释纠错 | audit-tracker-integrity |
| audit-release-evidence | 完成跨模块回归、四端功能声明、真实项目与升级验收，核验发布及实际安装内容 | audit-history-integrity |

Build order: audit-safety-containment → audit-map-consistency → audit-tracker-integrity → audit-history-integrity → audit-release-evidence

## 范围约束

- 本轮串行整改，各模块自身包含相关回归和文档，不到最后才补测试。
- 保留只读候选分析和人工指引，不自动创建 Agent、worktree、远端任务或执行合并/删除。
- 危险写入口的封闭是风险缓解，不宣称完整并行执行已经修复。
- 不添加新的任务事实源，不修改单 activeModule 契约，不开发新 controller 或执行数据库。
- 具体 F01–F13 验收与关闭定义见 [整改范围](../docs/research/2026-09-05-audit-remediation-scope.md)。

## 评审记录

- [x] 模块边界确认：沿用整改评审稿的五模块范围。
- [x] 依赖单向无环；本轮采用保守串行顺序。
- [x] module id 定稿，spec/plan/tracker 使用同一标识。
- [x] 构建顺序符合依赖拓扑。

评审依据：用户在明确询问“暂时禁用实验写操作、保留只读与成果、集中修复核心流程”后回复“继续”；据此进入正式 spec 阶段。模块 spec、实现计划及发布仍按各自门禁评审。
日期：2026-09-05。
Tracker：GitHub；initiative #138，模块 #139–#143，映射记录于 `.agent/state.json`。
