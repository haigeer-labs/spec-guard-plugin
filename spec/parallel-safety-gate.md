# Spec: parallel-safety-gate

## Objective

在 `parallel-readiness` 列出同层候选模块后，以模块作者显式声明的改动边界和最新
默认分支快照做保守冲突审查。它只可给出“可人工启动隔离并行”的建议，不能保证实现
期间不会新增冲突，更不能自动创建 worktree、任务或合并分支。

任何候选模块缺少完整边界声明，或与同组模块共享文件树、公共接口、迁移、全局配置、
锁文件或测试资源时，结果必须是 `needs-review` 或 `sequential-required`，绝不推测为安全。

## Tech Stack

- Python 3 标准库：解析严格 JSON 边界声明、验证原始相对路径、按组件比较规范路径，
  以不跟随链接的元数据检查输出稳定 JSON。
- Git：复用 `parallel-readiness` 的精确基线；只有调用方已获用户确认时才允许透传刷新。
- Bash 3.2：确定性本地仓库夹具回归。

## Commands

```bash
# 只审查本地已知基线；结果不能声称基于最新远端代码
python3 plugins/spec-guard/hooks/parallel-safety-gate.py --project .

# 用户明确确认联网刷新后，审查最新默认分支快照
python3 plugins/spec-guard/hooks/parallel-safety-gate.py --project . --refresh

/bin/bash plugins/spec-guard/hooks/test-parallel-safety-gate.sh
/bin/bash scripts/validate.sh
```

## Project Structure

```text
plugins/spec-guard/hooks/parallel-readiness.py
  → 提供唯一的基线与同层候选计算
plugins/spec-guard/hooks/parallel-safety-gate.py
  → 加载边界声明、冲突规则和分类结果
plugins/spec-guard/hooks/test-parallel-safety-gate.sh
  → 声明缺失、文件/API/资源冲突、保守降级回归
plugins/spec-guard/skills/spec-guard-ops/SKILL.md
plugins/spec-guard/commands/parallel-safety-gate.md
README.md
```

## Boundary Declaration Contract

每份候选模块的 `spec/<module-id>.md` 必须包含唯一的 `## Parallel Boundary` 标题，
下方紧接一个 `json` fenced code block。它是机器可读的声明，不是从模块名称、Git 历史
或自然语言描述猜出来的：

```json
{
  "paths": ["plugins/spec-guard/hooks/example.py"],
  "publicInterfaces": [],
  "migrations": [],
  "globalConfig": [],
  "testResources": []
}
```

- 五个字段均必须是数组；空数组表示该类资源明确不存在。
- `paths` 仅接受无通配符、无 `..`、仓库根相对的文件或目录路径；拒绝绝对/盘符/UNC、
  反斜杠、控制字符和歧义首尾空白。先保留/校验原始值，再规范化尾斜杠、重复分隔符和
  `.` 段按路径组件比较；目录拥有权与任一后代重叠即冲突，`src` 不与 `src-old` 重叠。
  根路径 `.` 覆盖全仓库。声明的新文件仍写预期相对路径。
- 有项目上下文时，已有组件逐级以不跟随链接的元数据检查；符号链接、失效链接、权限/平台
  故障、非普通组件及大小写或 Unicode 别名均为 `needs-review`，不读取外部目标内容。
  无项目上下文也为 `needs-review`；普通尚未创建路径只完成词法检查，不证明物理隔离。
- 其余字段为稳定、显式命名的资源标识；名称相同即冲突。`migrations`、`globalConfig`
  与 `testResources` 只要任一非空，默认要求串行，除非后续人工明确豁免。
- 现有基线中不存在的 `paths` 不算错误；分析器只校验它们不逃逸仓库，并把它们当作未来
  拥有权声明。不会从代码内容推断“实际还会改哪里”。

## Classification Contract

输出为每个 `candidate-only` 组提供精确基线、比较对和结论：

- `manual-parallel-eligible`：每个模块均有完整声明、项目上下文中的路径元数据未见不确定性、
  路径/API 没有交集，且迁移、全局配置、测试资源均明确为空。仍须用户确认后才可人工启动隔离工作区。
- `needs-review`：有缺失/无效声明或无法确认的边界；输出缺失字段或模块，不能推荐并行。
- `sequential-required`：检测到任意冲突或串行资源；输出具体冲突类别与模块对。

输出不得使用 `safe`、`automatic`、`approved` 或等价措辞。`--refresh` 的语义与
`parallel-readiness` 完全一致；刷新失败不产生成功报告。

## Testing Strategy

- 正向：两个候选模块拥有不重叠文件、接口和空资源声明时得到
  `manual-parallel-eligible`。
- 缺失：任一模块未写声明、缺字段或 JSON 无效时得到 `needs-review`。
- 冲突：相同文件、父目录与子文件、相同公共接口、迁移/配置/锁文件、相同测试资源均得到
  `sequential-required`，并列出原因。
- 安全：路径逃逸、绝对/盘符/UNC、反斜杠、通配符、控制字符与重复标题被拒绝；链接和别名
  不给绿灯，不读取或修改 state、Issue、分支或 worktree。
- 集成：复用 readiness 的精确 SHA 与 `--refresh` 成功/失败语义，不复制 Git 基线逻辑。

## Boundaries

- Always: 基于完整 SHA；把声明与推断分开；信息不足时保守降级；展示具体冲突证据。
- Ask first: 传递 `--refresh`；添加新的边界字段；对声明的串行资源做人工豁免。
- Never: 修改模块 spec 来补声明；自动创建/删除 worktree、任务、分支或 PR；修改
  `.agent/state.json`；扫描未声明的源代码后臆测所有权；绕开冲突仍建议并行。

## Success Criteria

1. 每个并行建议都能追溯到能力图、完整 SHA 与两份机器可读边界声明。
2. 所有缺失、不确定或冲突情况均不产生并行推荐；text/JSON 都可追溯到具体原因。
3. 同组无交集且无串行资源时，结果仅为 `manual-parallel-eligible`。
4. 该模块不改变现有单模块 tracker、状态、PR 与宿主任务生命周期。
