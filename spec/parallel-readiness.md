# Spec: parallel-readiness

## Objective

提供一个只读的并行开发就绪分析器。它从已评审的
`spec/CAPABILITY-MAP.md` 计算同一依赖层的模块候选组，并把分析使用的默认分支
ref、精确 commit SHA 与新鲜度写入结果。结果只表示“值得进入安全审查的候选”，
**绝不**表示这些模块已安全可并行。

用户可显式要求刷新远端默认分支；只有刷新成功的结果才可称为“基于最新 main
（或仓库默认分支）”。不刷新时，分析器必须明确说明它只使用本地已知快照。

## Tech Stack

- Python 3 标准库：解析能力图、解析 Git 输出、产生稳定 JSON 与文本报告。
- Git：解析 `origin/HEAD` 与 commit SHA；仅在用户显式传入 `--refresh` 时执行
  `git fetch`，不检出、不重置、不改工作目录。
- Bash 3.2：提供插件入口与确定性回归测试。

## Commands

```bash
# 仅分析本地已知的远端跟踪快照
python3 plugins/spec-guard/hooks/parallel-readiness.py --project .

# 用户显式要求以远端最新默认分支为基线
python3 plugins/spec-guard/hooks/parallel-readiness.py --project . --refresh

# 给宿主 skill / 自动化消费的稳定机器输出
python3 plugins/spec-guard/hooks/parallel-readiness.py --project . --format json

/bin/bash plugins/spec-guard/hooks/test-parallel-readiness.sh
/bin/bash scripts/validate.sh
```

## Project Structure

```text
plugins/spec-guard/hooks/capability_map.py
  → 唯一的能力图表格与依赖解析；由既有指纹逻辑和本模块共用
plugins/spec-guard/hooks/spec-digest.py
  → 改为调用共享解析器，保持既有 JSON 契约
plugins/spec-guard/hooks/parallel-readiness.py
  → 基线解析、依赖层候选计算、文本/JSON 报告
plugins/spec-guard/hooks/test-parallel-readiness.sh
  → 正向、非法图、freshness 与无副作用回归
plugins/spec-guard/skills/spec-guard-ops/SKILL.md
  → 增加 Codex 的只读 `parallel-readiness` 操作说明
plugins/spec-guard/commands/parallel-readiness.md
  → Claude Code 的同名只读命令入口
```

## Interface Contract

### Inputs

- `--project <path>`：待分析 Git 项目；默认当前目录。
- `--refresh`：唯一允许联网的开关。先解析 `origin/HEAD` 所指默认分支，再执行
  `git fetch origin <default-branch>`；失败时不退化为“最新”，报告失败并以非零退出。
- `--format text|json`：默认 `text`；`json` 供 skill 与回归测试消费。

### Output

JSON 至少包含：

```json
{
  "ok": true,
  "base": {"ref": "origin/main", "sha": "<40-hex>", "fresh": false},
  "candidateGroups": [
    {"layer": 0, "modules": ["docs", "tests"], "classification": "candidate-only"}
  ],
  "warnings": ["尚未验证远端新鲜度；传 --refresh 后才可称为最新主线。"]
}
```

- `candidateGroups` 只包含同层至少两个模块的组；单模块层不构成并行建议。
- `classification` 在本模块固定为 `candidate-only`。不得输出 `safe`、`approved` 或
  等价措辞；这些结论只能由后续 `parallel-safety-gate` 产生。
- 文本输出必须展示 `base.ref`、完整 SHA、新鲜度与“不等于安全并行”的提示。

### Capability-map Parsing

新增共享解析器，作为能力图表格与 `Depends on` 关系的唯一解析实现。既有
`spec-digest.py` 必须复用它，不能保留两份独立表格解析。解析器需接受 `—`、`-`、
空白作为“无依赖”，拒绝未知依赖、自依赖、循环、重复 module id 与不符合
kebab-case 的 id。

`Build order` 必须包含且仅包含所有模块，并满足每条依赖边的拓扑顺序；不符合时
报告图无效，不给出候选组。此严格性防止“看似可并行”的建议来自坏图。

## Testing Strategy

- 正向：两个无依赖模块形成 layer 0 候选组；下游模块只在其依赖所在层之后出现。
- 图校验：循环、未知依赖、重复 id、自依赖、非法 id、缺失或错误 build order 都拒绝。
- 基线：能解析非 `main` 默认分支；输出完整 SHA；未带 `--refresh` 标明
  `fresh=false`。
- 刷新：以本地 fake remote 验证 `--refresh` 更新远端跟踪 ref；fetch 失败不得把结果
  标成 fresh。
- 无副作用：未带 `--refresh` 时不调用 fetch、不改变 HEAD、索引、工作树或
  `.agent/state.json`。
- 回归：`spec-digest.py --selftest` 与完整 `scripts/validate.sh` 继续通过，证明共享
  解析器没有改变既有 digest 语义。

## Boundaries

- Always: 使用精确 SHA；把“候选”与“安全”严格区分；解析失败宁可拒绝也不猜测。
- Ask first: 调用带 `--refresh` 的联网刷新；改变能力图格式或既有 digest JSON 契约。
- Never: 创建 worktree、分支、Codex/Claude 子任务或 Issue；修改
  `.agent/state.json`；调用 `/next`；根据名称或历史提交猜测模块边界；把本地快照
  表述为最新远端代码。

## Success Criteria

1. 对合法能力图可稳定输出基线 SHA 与按依赖拓扑分组的候选模块。
2. 任意不完整或矛盾的能力图均拒绝给出候选，不产生误导性建议。
3. 未显式刷新时零网络、零工作区写入；显式刷新失败时不虚报新鲜度。
4. 既有能力图 digest 与 Spec Guard 验证链路保持兼容。
5. 输出不含任何“已经安全并行”的结论，也不触发宿主任务生命周期操作。
