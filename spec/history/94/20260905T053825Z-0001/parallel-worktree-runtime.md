# Spec: parallel-worktree-runtime

## Objective

在已领取模块 lease 后，安全创建、验证和回收 controller-owned Git linked worktree。它把
Git 工作区隔离作为可验证的资源，而不是把任意目录或宿主会话误当作隔离环境。

## Tech Stack

- Python 3 标准库：命令编排、受控 JSON 与路径校验。
- Git：`worktree add/list/remove/prune`、`rev-parse`、`status`、`merge-base`。
- Bash 3.2：临时裸仓库和失败夹具。

## Commands

```bash
python3 plugins/spec-guard/hooks/parallel-worktree.py provision --project . --run <run-id> --module <module-id>
python3 plugins/spec-guard/hooks/parallel-worktree.py verify --project . --worker <worker-id>
python3 plugins/spec-guard/hooks/parallel-worktree.py reclaim --project . --worker <worker-id> --confirm
/bin/bash plugins/spec-guard/hooks/test-parallel-worktree-runtime.sh
```

## Interface Contract

provision 只接受由 `parallel-execution-ledger` 签发的有效 manifest，创建命名分支和 linked
worktree，并返回绝对 `worktreePath`、`gitCommonDir`、HEAD、branch、owner=`spec-guard`。
任何子模块、路径逃逸、现有未登记 worktree、脏工作树、基线不相等或 setup/基线测试失败均拒绝。

reclaim 只允许移除 ledger 中 owner=`spec-guard` 的 worker，且仅在已合并或用户显式 discard
后执行。顺序固定为验证 → `git worktree remove` → 删除分支 → `git worktree prune`；PR/MR
创建后默认保留，不能因 worker 退出而自动删除。

## Project Structure

```text
plugins/spec-guard/hooks/parallel-worktree.py
plugins/spec-guard/hooks/parallel_worktree_lib.py
plugins/spec-guard/hooks/test-parallel-worktree-runtime.sh
```

## Testing Strategy

- 正常 create、重复名称拒绝、common-dir/HEAD/branch 不匹配拒绝。
- submodule、非 Git 目录、脏目录、setup 或基线测试失败不启动 worker。
- owner=host 或无 manifest 的 worktree 永不删除。
- 已合并回收与未合并拒绝回收在临时仓库中真实验证。

## Boundaries

- Always: 使用绝对路径，验证 linked-worktree 元数据和基线 SHA。
- Ask first: `--confirm` discard；新增 setup 运行约定。
- Never: 递归删除目录、清理用户/宿主创建的 worktree、用共享 checkout 执行写 worker。

## Success Criteria

1. 每个 provisioned worker 均位于正确 common-dir 下、基线已验证且可追溯。
2. 失败路径不会留下可被误用的 running worker 或删除非本插件资源。
3. 回收只在明确允许的状态发生。

## Parallel Boundary

```json
{
  "paths": ["plugins/spec-guard/hooks/parallel-worktree.py", "plugins/spec-guard/hooks/parallel_worktree_lib.py", "plugins/spec-guard/hooks/test-parallel-worktree-runtime.sh"],
  "publicInterfaces": ["parallel-worktree-cli-v1"],
  "migrations": [],
  "globalConfig": [],
  "testResources": []
}
```
