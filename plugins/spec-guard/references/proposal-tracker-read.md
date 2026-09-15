# Proposal tracker read

`proposal-tracker-read` 只读取并核验一个已发布 Proposal 的普通 GitHub Issue 或 GitLab
Issue。调用方必须先通过 `proposal-publication` 得到远端默认分支的 `published` Proposal，
然后显式传入平台和目标容器；此模块不会自行从 worktree、Git remote 或 Issue 标题推断它们。

```python
from proposal_tracker_read import as_json, read_tracker

# published.proposal 仅应来自已固定的 remote-default publication result.
result = read_tracker(published.proposal, "github", "owner/repository")
safe_result = as_json(result, "github", "owner/repository")
```

GitLab 的目标容器是正整数 project id：

```python
result = read_tracker(published.proposal, "gitlab", 17)
```

读取器使用 `gh api search/issues?...` 或 `glab api projects/<id>/issues?...` 的默认 GET
请求。它只把搜索结果当候选：最终身份必须来自正文中单独一行的完整 Proposal marker。
GitHub 以稳定的 `total_count` 证明搜索分页完整，并从响应的 `repository.full_name` 核验
容器；GitLab 显式查询 `state=all`，逐页读取至短页，因此关闭的 Proposal Issue 不会被当成
缺失。CLI、认证、网络、JSON、容器字段或分页无法核验时，不会猜测。

安全 JSON 结果只有：

- `verified`：包含 `platform`、`target`、`issueId` 与唯一 `stage`。
- `absent`：完整候选集没有完整 marker。
- `invalid`：包含稳定诊断码 `tracker-contract-invalid`，表示唯一性、容器、legacy marker
  或 Proposal 标签契约不符合。
- `unknown`：包含稳定诊断码 `tracker-read-unavailable`，表示读取完整性无法证明。

JSON 不包含 Issue 正文、评论、Proposal marker、raw API response、token、远端 URL 或原始
CLI 错误。`verified` 只是 tracker 事实核验；它不批准 Proposal、不创建任务、不改变标签，
也不代表能力图已晋级。
