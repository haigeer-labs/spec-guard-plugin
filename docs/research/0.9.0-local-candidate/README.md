# 0.9.0 本地候选验证

候选提交：`ff759e86e8c53afda4d229f6ae45ca82d9e1e290`。仅本地候选，尚未发布。

- 五项规定回归退出码均为 0；phase 134、verify 73、adapter 10 项通过。
- 首次导出权限为 0664，严格权限校验退出 1；规范包内文件为 Git 清单的 0644/0755 后重新构建通过，原目录与失败记录保留。
- 完整候选内容与 Git 提交的文件集合、字节、规范权限逐一相符；共 92 个源文件。
- 分发包缺仓库历史夹具时，历史测试 8 项初始化错误，退出 1；失败记录保留。补齐精确提交历史夹具的独立测试副本通过这 8 项；其余 21 项直接在分发包运行通过。
- 候选共 29 项聚焦测试通过；同一 alpha 夹具下源码/包各验证 GitHub、GitLab 的合法本地阶段、非法 state、缺 plan，均符合预期且无 gh/glab 调用。
- 只有 marketplace 和插件目录被导出，无活跃 state/spec/plan；未构建 MCPB 安装包。
- 回归日志见 regressions.json；包清单、逐文件 SHA256、命令和实际输出见 package-results.json。
- 可复现脚本 package.py 从调用者当前 Git HEAD 导出；固定输出根为 /private/tmp/sg-090-validation，已有同名 artifact/fixture 时拒绝覆盖，复跑先使用另一个输出根。

候选目录：`/private/tmp/sg-090-validation/spec-guard-0.9.0-ff759e8-verified`

归档：`/private/tmp/sg-090-validation/spec-guard-0.9.0-ff759e8-verified.tar.gz`

SHA256：`606d77177130b95867a46d89d23ab7752375ed317c13c43bedba6d0ddacf3599`

未运行：完整慢速变异测试（本次仅版本与说明变更）；真实宿主模型评测（禁止额外代理）；安装更新、宿主重启与真实 tracker 旅程（未授权）。
本轮 hook 显示 LOCAL_VALIDATION 但版本仍是缓存 0.8.0，不将其升级为 0.9.0 安装验收证据；未对缓存进行写入。

下一步需另行授权推送当前 codex 分支并创建面向 main 的 PR。第一步先只读核对 origin/main、版本 tag 与目标分支；展示/核对具体远端差异后才按授权写入。PR 创建并读回后停止，不自动合并、打 tag、发布、安装或重启。
