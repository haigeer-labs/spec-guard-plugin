# Spec: GitLab E2E

## Objective

在已安装 Codex 插件和真实 mGit 项目上验证 GitLab 初始化、hook 路由、Issue 关联与安全拒绝，保留可恢复的测试记录。

## Success Criteria

1. 已安装插件可执行 `setup-convention gitlab --host=codex`。
2. hook 输出 `tracker: gitlab`。
3. bridge 只接受非交互白名单参数。
4. 临时 Issue 关闭后项目无开放 E2E Issue。
