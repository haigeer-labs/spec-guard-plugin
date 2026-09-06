# 0.9.0 发布与安装操作预览（待确认）

本文件是操作提案，不是发布验收记录。核对日期：2026-09-06；代码候选 a9b8552，
分支 codex/local-stage-artifact-checkpoint；main 为 759f143。此次仅新增本预览，未改版本、
打 tag、推送、创建 Issue/PR、合并、更新安装或重启宿主。

## 事实与发布范围

- 三份版本清单仍为 0.8.0：plugins/spec-guard/.claude-plugin/plugin.json、
  plugins/spec-guard/.codex-plugin/plugin.json、plugins/spec-guard/manifest.json。
  最后一份是 Claude Desktop MCPB 清单；同步版本不代表完成 MCPB 打包或宿主验收。
- marketplace 使用相对 source ./plugins/spec-guard，没有独立 version 字段。
- 本地最新 tag 为 v0.8.0；尚未读取远端最新 refs，0.9.0 的远端可用性未确认。
- v0.8.0..main 有 121 个提交；插件目录 53 文件、5302 行新增、189 行删除。
  含旧并行原型及其后续暂停门禁、严格能力图、边界判定、tracker/workspace binding、
  历史完整性与发布证据能力。本次 main..a9b8552 的插件差异为 33 文件、908 行新增、17 行删除。
- CHANGELOG 有两段 Unreleased。发版应合并并完整列出基线与本次改动，不能只写 A/C/D。
- 拟定 0.9.0：理由是新增显式本地工作流与交互约定，并包含上述未发布基线。
  这是待确认的版本选择；没有整体合入暂停保存分支，也不恢复任何并行执行入口。

## 安装快照与命令依据

| 宿主 | 当前登记版本 | 来源 | 实际加载证据 |
| --- | --- | --- | --- |
| Codex | 0.8.0，installed/enabled=true | local marketplace /Users/vilin/Documents/gs/spec-guard-plugin；插件 source 为其 plugins/spec-guard | 本任务最新 hook 注入仍指向 Codex cache/0.8.0，误报 SPECED |
| Claude Code | 0.7.51，user scope | GitHub yizhongkaimail-collab/spec-guard-plugin | 安装登记 gitCommitSha=abb27872fe653fa415e1992aacf518004afbd118；本轮没有新宿主会话证据 |

已运行只读命令：git worktree list、git status --short、git tag --sort=-version:refname、
git log v0.8.0..main、git diff --stat、codex plugin list --available --json；读取 Claude
installed_plugins.json 与 known_marketplaces.json 中本插件条目。CLI --help 核对如下：

- codex plugin add spec-guard@spec-guard-marketplace --json：从已配置 marketplace 安装。
  本机没有 plugin update 子命令；marketplace upgrade 只刷新 Git 快照，不能用于本地 source。
  add 对既有安装的更新结果必须实测读取，不能仅凭帮助文字断言已更新。
- claude plugin marketplace update spec-guard-marketplace
- claude plugin update spec-guard@spec-guard-marketplace --scope user
  本机帮助明确提示 restart required；不自动加 --yes 接受潜在新安装命令。

[OpenAI 插件文档](https://learn.chatgpt.com/docs/plugins) 已打开作为背景参考；以上本机命令及
本地 source 行为边界以本轮 CLI 帮助和安装清单为依据，不据通用文档推断更新成功。

## 分步操作及停止条件

### 1. 当前请求确认：只整理本地 0.9.0 候选

确认后第一步在当前 codex 分支同步三份 manifest version，并整理 CHANGELOG 的两段
Unreleased 为 0.9.0 候选说明，保留已知限制、暂停边界与基线改动。
不修改 .agent/state.json，不创建 tracker 映射，不切换或合并 main。

随后运行项目五项规定检查；对精确候选提交导出普通临时目录 artifact，记录插件文件集合、
逐文件内容与模式，生成 ARTIFACT-MANIFEST.json；运行
python3 scripts/release-package.py validate <artifact-dir> 0.9.0。
该脚本仅核对四份清单及身份，必须另将完整插件目录与候选提交逐文件比较；
不能把清单通过写成完整内容一致。使用同一普通临时夹具、桩与对应 PLUGIN_ROOT 验证候选包。
归档包不携带本仓库的活跃 state/spec/plan，仅包含 marketplace 和插件分发内容与验证元数据。

停止条件：候选提交、包路径/内容清单、回归结果准备完毕，展示精确 SHA 后停下。
任何失败先定位，不进入外部操作。无需再次确认内部只读检查。

### 2. 远端接入与发布（另获授权，当前不执行）

先只读核对 origin/main 与 v0.9.0 是否存在；远端变化需重新评审候选，不覆盖已有 tag。
建议先明确授权推送当前分支并创建面向 main 的 PR，再由用户决定合并；PR 不附伪造的
Issue 编号，不删除分支。不得自动合并，也不得把暂停保存分支加入发布。
远端目的地：git@github-collab:yizhongkaimail-collab/spec-guard-plugin.git。

发布在确认候选进入 main 后另行授权：对核实后的精确提交创建 v0.9.0，并仅推送该 tag。
不使用 git push --tags 或 force，不跳过 pre-push。不自动创建 GitHub Release 页面；
若需要发布附件，须另列文件名、SHA256 与 release body 后确认。
仓库现有 Actions 只有 validate，无自动发布 job；本轮未查询 Actions 账户当前可用性。

停止条件：读回远端 ref 并确认精确提交。请求结果未知时只读查询，不盲目重复写入；
权限被拒绝即停，不改协议绕过。

### 3. 安装更新（两端分别授权）

Codex：当前 marketplace 指向 main checkout，需先由用户授权更新该 checkout 至已核实发布
提交；重新确认其无未提交改动、无其他任务占用，不能擅自切换或快进。随后运行上述
codex plugin add 命令，读取返回路径/版本，逐文件比较安装内容与候选包。
如果 add 没有更新或行为不明，停下记录；不自动 remove/reinstall 或改缓存。

Claude Code：远端默认分支已含发布版本后，依次运行上述 marketplace update 和 plugin update。
每步读取结果，重新读取安装登记与缓存文件，与候选内容核对。一次失败或结果未知就停下。

此阶段最多证明磁盘安装内容一致，不能证明宿主已加载。
Codex 导入生成的 migrated-command-skills 等派生文件需与对应源命令单独核对；
不要只比较版本字符串、仓库 HEAD，也不要忽略全部额外文件。

### 4. 宿主验收（另获授权）

保存当前任务后，由用户决定新会话/重启；核对新会话 ID、版本、hook 实际路径与文件内容。
Codex 按项目要求在 /hooks 审核信任；只有用户已授权才进行该步骤。
不运行会启动额外 agent 的 codex exec / claude -p。本任务禁止额外代理的约束仍然有效；
现有 codex-plugin-smoke.sh 真跑会调用 codex exec，因此本次只保留已完成的 --selftest 证据。
如要运行真 smoke，必须明确变更这项范围，否则在用户开启的会话中人工观察并记录。

对同一个 alpha 本地夹具验证：显示活跃模块和 tracker 尚未激活；没有远端调用或同步建议；
非法 state/缺产物继续失败，旧流程门禁保留。D 的七个场景在实际交互中逐一观察五项检查点内容，
尤其“继续”、拒绝、未知结果与取消后的授权边界。只记录实际执行过的宿主，不跨宿主外推。
停止条件：每个已授权宿主结果、证据路径或明确 not-verified 原因已记录；不开展真实 tracker 写旅程。

## 当前证据与恢复

源码五项规定检查与 29 项聚焦测试已通过，见 local-workflow-review-validation-20260906.json。
本轮只有只读核对与预览文档，无行为改动，不重复源码回归。安装、真实宿主、真实项目验收未完成；
当前不能宣称 release-ready 或 installed/host/project-verified。

失败时保留分支、日志和历史账本；不删除资源、不自动降级到可能含旧并行写入口的 0.8.0。
安装异常停用/回退也先展示宿主、版本和受影响配置后授权。取消会使本预览的待执行授权失效，
重新“继续”不能恢复已暂停的并行 initiative。
