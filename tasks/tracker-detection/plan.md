# Implementation Plan: Tracker Detection

## Overview

为两个只读 hook 加入一致的 GitLab、GitHub 与本地 tracker 识别，不改变显式
`state.json` 配置的优先级。GitLab 自建实例由已认证 `glab` 的仓库识别确认；域名
字面匹配只可作为无歧义的快速路径，不能成为唯一判据。

## Architecture Decisions

- 显式 `tracker` 值优先，保持现有 `github`、`gitlab`、`none` 与其他 tracker 兼容。
- 远端解析只提取 host 与 `namespace/project`，不从仓库路径关键词推断平台。
- GitHub 维持现有 host 规则；GitLab.com 可直接识别；自建 GitLab 仅在 `glab` 对当前
  remote 的只读识别成功时确认为 GitLab。
- 探测出错、CLI 缺失、未认证或命令超时都回落 `none`；不发起登录、不写配置、不读取 token。
- `phase-guard.sh` 与 `verify-artifacts.sh` 使用同一顺序，并分别有回归用例，防止漂移。

## Task List

> Tasks tracked in GitHub Issues #36.

### Phase 1: Detection contract

- #40 定义 GitLab tracker 探测测试契约
- #41 在 phase-guard 中实现安全的 GitLab 探测（blocked by #40）

### Phase 2: Verifier parity

- #42 让 verify-artifacts 与 GitLab 探测保持一致（blocked by #41）

### Checkpoint

- `bash scripts/validate.sh` 全绿。
- `git diff --check` 无输出。
- 评审 diff，确认无 token、无网络写入、无 GitHub 回归。

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| 自建 GitLab host 不含 `gitlab` | 高 | 使用已认证 `glab` 的只读仓库识别；mGit fixture 覆盖。 |
| `glab` 不存在或网络不可达 | 高 | 超时/失败一律回落 `none`，不降级为 GitHub。 |
| 两个 hook 规则漂移 | 中 | 两处均有独立用例与全量回归。 |
| 每轮 hook 网络调用变慢 | 中 | 仅在无显式配置且 host 不可直接判定时调用，并使用短超时。 |

## Open Questions

无。真实 GitLab E2E 留在依赖完成后的 `gitlab-e2e` 模块执行。
