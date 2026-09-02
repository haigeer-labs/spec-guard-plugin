# Implementation Plan: initiative-lifecycle

## Overview

在不改变当前 `spec/`、`tasks/` 与 `.agent/state.json` 路径契约的前提下，实现 initiative 的
暂停、恢复与终态 checkpoint。账本读写只调用 `capability-history.py`。

## Task List

> Tasks tracked in GitHub Issues #7.

- #17 实现 pause 的 dry-run 与失败保护

- #18 实现 pause 与终态 checkpoint（blocked by #17）

- #19 实现 resume（blocked by #18）

- #20 接入总校验与宿主入口（blocked by #19）

## Risks

- 文件移动中断：始终先复制、验证、写账本，最后才清理源路径。
- 恢复覆盖当前工作：必须暂停当前 initiative，并要求确认。
- 账本与文件不同步：每个 checkpoint 先用账本工具验证再报告成功。
