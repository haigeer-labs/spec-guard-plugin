# Capability Map: [填写 Initiative 名称]

> 由 `/spec` 的 Phase 0 产出。**必须经人工评审后才能往下走。**
> Addy 原文：把图搞错代价很大，评审十行不算什么。

| Module id | Responsibility | Depends on |
|---|---|---|
| example-a | 一句话说清这个模块负责什么 | — |
| example-b | ... | example-a |

Build order: example-a → example-b

---

## 评审记录

- [ ] 模块边界确认（砍掉或替换一个模块，不需要重写其他模块的需求）
- [ ] 依赖方向单向无环（互相依赖 = 它们本来就是一个模块）
- [ ] module id 已定稿（kebab-case，之后绝不改名）
- [ ] 构建顺序符合依赖拓扑

评审人：
日期：
