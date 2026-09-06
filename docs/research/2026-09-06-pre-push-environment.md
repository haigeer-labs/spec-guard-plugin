# pre-push 的 Git 仓库环境隔离

## 已确认设计与范围

用户在发布候选只读核对后，确认修复原 pre-push 测试污染仓库配置的问题。
实现范围仅为 scripts/install-git-hooks.sh 生成的 hook、独立临时仓库回归与 validate 接入。
不更新当前安装的 hook，不推送、合并、打 tag、发布、修改插件缓存或启动额外代理。
本任务分支 codex/fix/pre-push-git-environment，基于 61b19ef；其内容已通过 PR #199 合并。

## 原因与最小修复

真实 Git push 调用 pre-push 时提供仓库级环境变量。原 hook 直接运行会创建临时 Git 仓库的
测试，这些 Git 子进程仍指向推送仓库；旧测试可显示全绿，但修改原配置的 bare、身份和 remote。

先在原环境解析推送 worktree 的根目录，再通过 git rev-parse --local-env-vars 获取 Git
声明的仓库级变量，并在当前 hook shell 中逐个 unset。随后按原顺序运行三项检查，每项仍只跑一次。
不使用 --no-verify，不硬编码仅 GIT_DIR，也不清除全部用户环境；根目录或变量枚举失败即非零退出。
不引入 subshell 管道导致清除无效。保留原有检查失败聚合，任一检查失败阻止 push。

## 复现与验收

命令：python3 -B scripts/test_pre_push_environment.py。
全部仓库均在 TemporaryDirectory 中，push 目标是本地裸仓库，不使用真实 remote 或宿主模型。
安装器复制进临时仓库，在那里生成并安装 hook；三个检查替身真实执行 git init --bare、git init
及 git config，模拟原失败机制；只使用文件日志记录调用。

- 普通 checkout 与 linked worktree：三项检查各运行一次，push 成功，源仓库公共 config 字节完全不变。
- validate、phase、verify 分别失败：三项仍各运行一次，push 非零，目标裸仓库没有 probe ref，源配置不变。
- 旧安装器 RED：3 个测试方法、4 处失败，捕获 bare 从 false 变 true 和配置覆盖；修正版 GREEN：3 方法通过（含 3 个失败门禁子场景）。
- 项目五项规定回归结果与原始日志见 2026-09-06-pre-push-environment-evidence.json。

## 生效边界与下一检查点

这是生成脚本的持久修复；现有 .git/hooks/pre-push 尚未重装，仍是旧代码。
源码通过不等于安装生效，不能直接恢复不带隔离措施的真实 push。
插件分发目录及 0.9.0 候选包内容不变，不把这次维护修复写成新的宿主验收。

下一步只读审阅本次 diff 与回归证据，无需额外确认；审阅完成后停止。
如需推送本分支或更新当前安装的 hook，须展示确切操作再授权；不得使用此前 PR #199 的授权。
