# 贡献指南

## 提 PR 前

```bash
bash scripts/validate.sh
bash plugins/spec-guard/hooks/test-phase-guard.sh
```

两个都绿才提。CI 会跑同样的检查。

## 改 phase-guard.sh

这是核心文件，改动有三条硬约束（详见 [CLAUDE.md](CLAUDE.md)）：

1. 默认不生效 —— 未声明约定的仓库必须静默 `exit 0`
2. 探测失败就降级 —— **绝不能报假断链**
3. 只读 —— 它是探测器，不做任何写操作

**改了状态机逻辑必须加测试用例。** 测试文件在 `plugins/spec-guard/hooks/test-phase-guard.sh`。

## 加新的断链检测

新增一条前先问：

- [ ] 这个「断链」有没有合理的例外？（有的话不该报，或者要可配置）
- [ ] 探测依赖的东西不存在时会怎样？（必须降级，不能误报）
- [ ] 检测成本多少？（hook 在每次发言前跑，超过 1s 有体感）

**宁可漏报也不要误报。** 假断链会让人关掉整个机制。

## 加新命令

1. `plugins/spec-guard/commands/<name>.md`
2. 必须有 frontmatter（`validate.sh` 会检查）
3. 在 README 的命令表里补一行

## 发版

见 [CLAUDE.md](CLAUDE.md#发版)。**版本号不升，使用者收不到更新。**

## 不接受的 PR

- fork 或 vendored 上游 agent-skills 的文件
- 给 phase-guard.sh 引入 `jq` 之类的硬依赖
- 让 hook 做写操作
- 在本仓库的 CLAUDE.md 里写激活字符串（会导致插件在自己仓库上激活）
