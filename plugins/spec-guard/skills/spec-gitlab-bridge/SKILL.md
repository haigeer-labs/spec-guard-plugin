---
name: spec-gitlab-bridge
description: 在 Spec Guard 产物与 GitLab Issues、Merge Requests 之间执行安全的 GitLab 工作流。
---

# Spec Guard GitLab Bridge

## 前置检查

```bash
glab auth status
glab repo view
```

API 必须可用；认证失败时停止，不要回退到 `gh`。

## GitLab 15.3 能力边界

- Issue 与 Merge Request 可用。
- Issue link 只能建立 `relates_to`；它不是父子或阻塞关系。
- Work Items、父子 Issue、`--parent`、`--blocked-by` 不可依赖；不以 label 模拟。

## 命令

```bash
glab issue create --repo <group/project> --title '<title>' --description-file <file>
glab api -X POST 'projects/<project-id>/issues/<iid>/links' \
  -f target_project_id=<project-id> -f target_issue_iid=<iid>
glab mr create --repo <group/project> --source-branch <branch> --target-branch <branch>
glab mr merge <iid> --repo <group/project> --yes --remove-source-branch
```

始终在输出中标明 `relates_to` 是降级关联。未知 API 版本或 404 时停止并说明该能力不可用。
