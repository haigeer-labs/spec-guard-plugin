# Capability Map: Documentation Governance

## 目标

让项目以需求、架构与消费者契约等上游文档约束模块实现，并让文档影响在计划和交付时显式收口；不以代码反推文档真相，不强制固定文档集合。

## 模块

| Module id | Responsibility | Depends on |
|---|---|---|
| documentation-baseline | 定义显式启用的项目级文档基线协议、解析事实和初始化入口 | — |
| documentation-impact | 在模块 Spec、Plan 与交付前表达并收口对文档基线的遵循、补全、变更或不适用结论 | documentation-baseline |
| documentation-verification | 提供只读核验、保守提醒和跨宿主回归，确保缺失或未知不被伪装为文档完成 | documentation-baseline, documentation-impact |

Build order: documentation-baseline → documentation-impact → documentation-verification

## 评审记录

用户于 2026-09-10 确认：文档不是代码的一比一快照，而是需求、产品方案、技术架构和消费者体验对实现的上层约束。项目必须显式回答其目标、架构约束和开发/验证入口；ADR、接入、用户、运维与合规文档按项目特征触发。默认采用提醒式治理，不从代码猜测文档是否过期。
