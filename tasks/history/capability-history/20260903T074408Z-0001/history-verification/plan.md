# Implementation Plan: history-verification

## Overview

实现只读历史证据校验、orphan 检测和宿主接入；不修改或删除用户历史文件。

## Task List

> Tasks tracked in GitHub Issues #8.

- #22 实现历史 checkpoint 完整性校验
- #23 检测 orphan 历史证据并兼容旧项目
- #24 接入历史校验入口与总回归

## Risks

- 旧项目没有账本时必须返回未验证，避免阻断既有工作流。
- orphan 仅报告，不自动清理。
