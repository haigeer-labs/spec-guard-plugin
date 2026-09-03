# Spec: parallel-guidance

## Objective

把 `parallel-safety-gate` 的结果转成用户确认前可执行的并行开发建议：候选模块、精确
基线 SHA、推荐的隔离 worktree/子任务名称、每个 worker 的边界、汇合顺序与验证清单。
它只提供指引，不能创建、调度、标题更新、归档或删除任何宿主任务和 Git worktree。

## Tech Stack

- Python 3 标准库：消费 safety-gate JSON，生成稳定文本/JSON 指引。
- Git：只读取当前基线与工作区状态；不创建 worktree、分支或提交。

## Commands

```bash
python3 plugins/spec-guard/hooks/parallel-guidance.py --project .
python3 plugins/spec-guard/hooks/parallel-guidance.py --project . --refresh
/bin/bash plugins/spec-guard/hooks/test-parallel-guidance.sh
```

## Guidance Contract

- 仅对 `manual-parallel-eligible` 组输出“建议人工并行”；其余分类展示原因与串行建议。
- 每个建议包含父 initiative、模块 id、基线 SHA、建议分支
  `codex/parallel/<module-id>`、建议标题 `[SG 手动并行｜待汇合] <module-id>`，及明确的
  “用户自行创建并负责回收”说明。
- 汇合前清单必须要求：各 worker 工作树干净、变更仍符合声明边界、各自测试通过、按
  capability map 的依赖拓扑依次合并、在整合分支运行完整校验。
- 未提供 `--refresh` 时复用并展示 `fresh=false`；`--refresh` 仍需宿主先获得用户确认。

## Testing Strategy

- eligible 组生成每模块指引与汇合清单；needs-review/sequential 组不生成 worker 建议。
- 基线 SHA、新鲜度与模块顺序来自 safety gate，不能自行重新计算。
- 文本中不存在“自动创建”“自动回收”“安全保证”等承诺。

## Boundaries

- Always: 明示用户确认和人工生命周期责任；保留安全门证据与完整 SHA。
- Ask first: 透传 `--refresh`；任何未来宿主任务或 worktree API 调用。
- Never: 调用 Codex/Claude 任务 API；执行 `git worktree add/remove`、`git branch`、
  `git merge`、`git push`；修改 state、Issue 或现有工作流。

## Success Criteria

1. 用户可从一份报告获得可复制的手动并行步骤和可靠汇合清单。
2. 不符合安全门条件的模块永远不会被推荐为并行 worker。
3. 插件保持对宿主任务与 Git worktree 生命周期的零控制权。
