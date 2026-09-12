# 发布流程

发布的完成标准不是 Git 已推送，而是 marketplace 中安装的插件副本与已发布内容一致。

## 发布前

1. 确认 Claude 与 Codex manifest 的版本一致。
2. 按用户影响更新 `CHANGELOG.md`。
3. 运行 `/bin/bash scripts/validate.sh` 与受改动面影响的聚焦测试。
4. 若修改 Codex manifest、hook 或技能，运行 `/bin/bash evals/codex-plugin-smoke.sh --selftest`。

## 发布

1. 提交已验证的变更。
2. 创建匹配版本的 Git tag。
3. 推送提交和 tag。
4. 刷新 marketplace，并在新会话中安装/启用更新后的插件。
5. 在 `/hooks` 审核 `UserPromptSubmit`，然后从临时消费者项目运行真实 Codex smoke。

不同宿主的 marketplace 刷新命令与权限策略可能不同；先以 `codex plugin marketplace --help`
或宿主 UI 显示的当前命令为准，不要假定工作区 HEAD 已被运行时自动采用。

## 发布后核对

```bash
codex plugin marketplace list
codex plugin list --json
```

核对 `spec-guard@spec-guard-marketplace` 已启用、版本正确且 `source.path` 是预期来源。真实
smoke 的 `--expected-source` 必须与该字段精确一致：本地 marketplace 通常是候选工作区，Git
marketplace 则是 Codex 的缓存副本。不要猜测这两个路径相同。

如果开发分支与安装副本版本不同，先判定是“待发布候选”还是“本地分支落后于发布线”。不要仅为
消除版本差异改 manifest；应在独立的合并或发布任务中决定版本与变更来源。
