---
description: 从当前项目移除 spec-guard 的约定（保留你的 spec 和 plan 内容）
allowed-tools: Bash, Read, Edit
---

移除本项目的 spec-guard 约定。**先确认用户真的要移除**，说明会发生什么。

## 会移除

- `CLAUDE.md` 中 `<!-- BEGIN:agent-skills-convention -->` 到
  `<!-- END:agent-skills-convention -->` 之间的内容（含标记本身）

## 不会碰

- `spec/` `tasks/` 里的内容 —— 那是用户的规格和计划，不是工具的
- `.agent/state.json` —— 里面有 issue 编号映射，删了就找不回来
- GitHub 上已创建的 issue

## 步骤

1. 确认 `CLAUDE.md` 存在且含标记：

```bash
grep -n "BEGIN:agent-skills-convention" CLAUDE.md
```

2. 删除标记之间的内容（含标记）。**用精确的行范围，不要正则误删用户内容。**

3. 验证 hook 已停止生效：

```bash
CLAUDE_PROJECT_DIR=$(pwd) bash "${CLAUDE_PLUGIN_ROOT}/hooks/phase-guard.sh"
```

无输出即为成功。

4. 告知用户：

```
约定已移除。以下内容保留，确认不需要后自行删除：
  spec/               你的能力图和模块规格
  tasks/              你的计划文档
  .agent/state.json   模块 ↔ issue 编号映射

插件本身仍然装着。要完全卸载：/plugin uninstall spec-guard
```
