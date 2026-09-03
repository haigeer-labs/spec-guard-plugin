# Implementation Plan: parallel-guidance

## Overview

将安全门分类转换为人工执行的 worker 命名、边界提醒和汇合验证清单；保持零宿主与 Git 生命周期控制。

## Task List

1. 实现 `parallel_guidance.py`，复用 safety gate 报告并只为 `manual-parallel-eligible` 生成稳定 JSON/text 指引；测试基线、新鲜度、命名与非 eligible 降级。
2. 添加 `parallel-guidance.py` 显式 CLI 与 Claude/Codex 入口；适配器测试禁止 hook、任务 API 与 worktree 命令。
3. 更新 README，运行 focused tests 与 `scripts/validate.sh`。

## Checkpoint

- 不产生 `git worktree`、`git branch`、`git merge`、任务 API、state 或 Issue 写入。
- 全量校验通过，且报告明确由用户创建/回收 worker。
