# Spec: Tracker Detection

## Objective

让 Spec Guard 在不要求用户手工维护 tracker 配置的前提下，为当前 Git 仓库选择
`github`、`gitlab` 或 `none`。显式的 `.agent/state.json.tracker` 始终优先；自动探测
必须识别 GitHub、GitLab.com、GitLab 自建实例及本次实测的 `mgit.lgroup.co`。无法确认
远端平台时选择 `none`，绝不把不确定的托管服务误当成 GitHub 或 GitLab。

## Commands

```bash
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash scripts/validate.sh
git diff --check
```

真实 GitLab 回归在后续 `gitlab-e2e` 模块执行，使用：

```bash
glab repo view --repo hqdf/web/x9-live-player
glab auth status --hostname mgit.lgroup.co
```

## Project Structure

```text
plugins/spec-guard/hooks/phase-guard.sh       tracker 识别和阶段输出
plugins/spec-guard/hooks/verify-artifacts.sh  tracker 相关产物校验
plugins/spec-guard/hooks/setup-convention.sh  初始化 tracker 约定
plugins/spec-guard/hooks/test-*.sh            shell 回归测试
plugins/spec-guard/skills/                    各 tracker 的操作说明
```

## Code Style

保持 POSIX 兼容的 Bash 写法、显式返回值和现有中文诊断风格；检测函数只返回平台名，
不在其中创建 Issue、修改远端或提示登录。

```bash
detect_tracker() {
  explicit_tracker || detect_remote_tracker || printf '%s\n' none
}
```

## Testing Strategy

- shell 单元回归覆盖显式 tracker、无 remote、GitHub remote、GitLab.com remote、
  自建 GitLab remote 和 CLI 探测失败。
- mGit 场景用可替换的 `glab` 桩验证，保证域名不含 `gitlab` 时不会降级为本地。
- 不可达、未认证或 CLI 缺失时验证不会误选另一托管平台。
- 完成模块后运行全量 `scripts/validate.sh` 与 `git diff --check`。

## Boundaries

- Always: 显式配置优先；探测只读；未知平台回落 `none`；保留 GitHub 既有结果。
- Ask first: 更改 `.agent/state.json` 已有字段语义；增加第三方 CLI 依赖；改变 CI。
- Never: 根据域名中是否含 `gitlab` 作为自建 GitLab 的唯一依据；在检测中写入
  GitHub/GitLab；输出或读取认证 token。

## Success Criteria

1. `tracker=github`、`tracker=gitlab` 与 `tracker=none` 的显式值保持最高优先级。
2. GitHub remote 保持选择 `github`。
3. `git@mgit.lgroup.co:hqdf/web/x9-live-player.git` 在已认证 `glab` 环境选择 `gitlab`。
4. 没有 remote、CLI 不存在、认证失败或未知宿主均选择 `none`，且不输出 GitHub 专属建议。
5. 本模块不会尝试解决 Issue 层级、MR 命令或 GitLab 能力降级；这些属于后续模块。

## Open Questions

无。GitLab 自建实例通过已认证 `glab` 的仓库识别确认，而非 host 名称猜测。
