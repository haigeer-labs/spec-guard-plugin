# Spec: history-verification

## Objective

为 `spec/CAPABILITY-HISTORY.json` 提供历史证据校验：验证账本结构、事件状态、checkpoint
引用文件与 SHA-256，并报告 orphan、缺失、篡改与路径逃逸。旧项目或尚无账本时必须明确为未验证，
不得产生假阳性。

## Tech Stack

- Python 3 标准库：复用 `capability-history.py` 的账本加载与完整性校验。
- Bash 3.2：提供确定性 hook 入口和回归测试。

## Commands

```bash
/bin/bash plugins/spec-guard/hooks/test-history-verification.sh
/bin/bash scripts/validate.sh
```

## Project Structure

```text
plugins/spec-guard/hooks/verify-history.sh
plugins/spec-guard/hooks/test-history-verification.sh
plugins/spec-guard/hooks/capability-history.py
spec/history/<initiative-id>/<checkpoint-id>/
tasks/history/<initiative-id>/<checkpoint-id>/
```

## Verification Contract

- 账本不存在时输出未验证并成功退出；不把未启用历史记录当作错误。
- 账本存在时验证 schema、事件转移及全部引用证据的路径和摘要。
- history 目录中不被账本 checkpoint 引用的文件或目录报告为 orphan。
- 引用文件缺失、摘要不符或越过项目根时以非零退出，并说明原因。

## Testing Strategy

- 正向：有效账本及 map/spec/plan/state checkpoint 全部通过。
- 反向：篡改摘要、删除证据、非法路径及 orphan 历史目录均失败。
- 兼容：没有账本的项目返回未验证且不修改文件。

## Boundaries

- Always: 复用 `capability-history.py`；只读校验；对错误给出明确诊断。
- Ask first: 改动账本 schema、移动或删除历史证据。
- Never: 自动删除 orphan；把缺失账本解释为历史已验证；复制第二份账本 schema。

## Success Criteria

1. 可验证当前与全部历史 checkpoint 的完整性。
2. orphan、缺失、篡改和路径逃逸可被可靠区分并拒绝。
3. 未启用账本的既有项目保持兼容且无假阳性。
