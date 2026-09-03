# Spec: GitLab Workflow

## Objective

让 Spec Guard 在 GitLab 项目中以 `glab` 管理 initiative、模块和任务 Issue，并通过
Merge Request 交付；在 GitLab 15.3 缺少 Work Items、父子 Issue 和阻塞语义时，明确
降级为平面 Issue 与 `relates_to` 链接，绝不伪造 GitHub 层级或依赖。

## Commands

```bash
glab issue create --repo <namespace/project> --title <title>
glab api -X POST projects/<id>/issues/<iid>/links -f target_project_id=<id> -f target_issue_iid=<iid>
glab mr create --repo <namespace/project> --source-branch <branch> --target-branch <branch>
glab mr merge <iid> --repo <namespace/project> --yes
```

## Testing Strategy

- 用 `glab` stub 覆盖命令生成与失败降级。
- 在 `hqdf/web/x9-live-player` 验证 Issue、`relates_to`、MR 和清理。
- 不调用不存在的 Work Items 或 GitHub-only `--parent` / `--blocked-by` 参数。

## Boundaries

- Always: 使用 `glab`；保留 Issue/MR 编号；报告降级。
- Ask first: 删除 Issue/MR 或重写远端历史。
- Never: 将 `relates_to` 说成阻塞或父子关系；输出 token。

## Success Criteria

1. GitLab workflow 不执行 `gh` 命令或 GitHub-only flags。
2. GitLab 15.3 的 Issue、链接和 MR 路径可执行。
3. 不支持的层级/依赖会被明确标注为降级。
4. GitHub 与本地模式不改变。
