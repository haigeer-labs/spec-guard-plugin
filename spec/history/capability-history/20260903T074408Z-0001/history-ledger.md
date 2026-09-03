# Spec: history-ledger

## Objective

为 spec-guard 提供一个可提交、机器可读、可审计的 initiative 生命周期账本：
`spec/CAPABILITY-HISTORY.json`。它记录每个 initiative 从 `created` 开始，到暂停、恢复和
终态的追加事件及能力图 checkpoint，使 AI 能在不扫描或猜测文件名的情况下查询项目曾经
开发过哪些模块、它们的依赖、状态、Issue 与证据位置。

它不管理当前正在做哪个模块；这仍是 `.agent/state.json.activeModule` 的职责。

## Tech Stack

- Bash 3.2：插件入口与 hook 调用。
- Python 3 标准库：JSON schema 校验、摘要计算与原子写入；不得引入 `jq` 或第三方依赖。
- Git：账本与 checkpoint 作为项目版本控制中的证据。

## Commands

```bash
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh
/bin/bash evals/codex-plugin-smoke.sh --selftest
```

模块实现后应额外提供账本工具自身的 `--selftest`，并纳入 `scripts/validate.sh`。

## Project Structure

```text
spec/CAPABILITY-HISTORY.json                       # 项目中的生命周期账本
spec/history/<initiative-id>/<checkpoint-id>/      # 历史能力图与 spec 快照
tasks/history/<initiative-id>/<checkpoint-id>/     # 历史 plan 快照
plugins/spec-guard/hooks/capability-history.py     # 唯一账本读写与验证实现
plugins/spec-guard/hooks/test-capability-history.sh# 账本正反向回归
```

`spec/CAPABILITY-MAP.md`、`spec/<module-id>.md`、`tasks/<module-id>/plan.md` 和
`.agent/state.json` 不在本模块内改变格式或职责。

## Code Style

账本结构只使用标准 JSON 基元；路径一律为项目根相对路径。事件只追加，不修改旧事件：

```json
{
  "type": "paused",
  "at": "2026-09-02T16:00:00+08:00",
  "checkpoint": {
    "map": { "path": "spec/history/payment-v2/cp-001/CAPABILITY-MAP.md", "sha256": "..." },
    "modules": [
      {
        "id": "payment-api",
        "responsibility": "支付 API。",
        "dependsOn": [],
        "status": "completed",
        "issue": 437,
        "spec": { "path": "spec/history/payment-v2/cp-001/payment-api.md", "sha256": "..." },
        "plan": { "path": "tasks/history/payment-v2/cp-001/payment-api/plan.md", "sha256": "..." }
      }
    ]
  }
}
```

读取失败必须返回明确的“未验证”结果，不能将解析错误、缺失字段或空账本解释为通过。

## Testing Strategy

- schema 正向：合法 `created → paused → resumed → completed` 事件流可读取，最后状态可推导。
- schema 反向：重复 initiative ID、首事件不是 `created`、非法状态转换、重复模块 ID、绝对路径、
  逃逸路径和无效摘要均失败。
- 原子性：写入中断或目标冲突时原账本字节不变。
- 查询：用 `initiative-id/module-id` 精确返回最近 checkpoint 的模块证据；同名模块跨 initiative
  不冲突。
- 完整性：账本记录的 map/spec/plan 缺失或摘要不一致时返回失败，而不是通过。

## Boundaries

- Always: 使用一个 Python 实现计算历史文件摘要；所有路径在项目根内；先验证后写入。
- Ask first: 更改既有 `state.json` 字段、修改当前能力图格式、迁移或移动用户项目文件。
- Never: 在 JSON 中复制 spec/plan 全文；修改旧事件；将未知迁移记录写为 `completed`；引入 jq。

## Success Criteria

1. `CAPABILITY-HISTORY.json` 能记录完整 initiative 事件流和每个 checkpoint 的模块能力图。
2. 每个历史模块可经 `initiative-id/module-id` 定位到它的 spec、plan、Issue 与状态。
3. 解析、路径或完整性错误不会产生假通过。
4. 账本的新增协议不改变上游 agent-skills 或现有 spec-guard 当前工作区协议。

## Decisions

- checkpoint ID 使用 `YYYYMMDDTHHMMSSZ-NNNN`：UTC 时间戳加 initiative 内四位递增序号，
  既按时间排序，也不会在同秒内冲突。
- 初始 `created` checkpoint 中尚未生成的模块 spec/plan 统一使用 `null`，让 schema 与校验
  逻辑明确区分“尚未产生”与“应存在但丢失”。
