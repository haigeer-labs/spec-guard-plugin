# Audit Tracker Integrity — Checkpoint A: Recovery Foundation

日期：2026-09-05。模块：`audit-tracker-integrity`。对应任务：#175、#176、#177。

## 审查结论

GitLab capability-map 投影现在以完整的 v2 HTML marker 作为恢复身份：

- initiative：`kind=initiative + goalDigest`；
- module：`kind=module + module id + rowDigest`；
- 标题、部分 marker 和没有 description 的搜索候选都不能建立身份；
- 零匹配才允许创建；唯一完整匹配可恢复；多个完整匹配、外部项目、坏 JSON、API
  失败或不完整页都 fail-closed，不做补偿 POST；
- 已记录 IID 必须回读并匹配当前 digest/marker，陈旧、外来或不完整 state 不会被覆盖。

同步器通过 `glab api --paginate` 读取搜索结果，依赖当前 `glab` 的“逐页取完”契约；
如果该命令失败，恢复停止，而不是将首页当作完整结果。每一次远端 create 或 marker
恢复后，才以唯一临时文件、`fsync` 与 `os.replace` 原子写回既有的
`initiative.goalDigest` / `modules.<id>.rowDigest` 映射。`activeModule` 仅在全部模块
验证后且原先为空时初始化。

## RED → GREEN 证据

1. 新增 identity 测试最初因 `gitlab_tracker` 不存在而失败；实现后覆盖完整 marker、
   标题/部分 marker、多个匹配、坏 JSON、外部 project 与 `description: null`。
2. 扩展 GitLab sync 桩后，旧同步器在重复同步（未存 digest）、响应丢失、陈旧 state
   与重复 marker 用例失败；重构后全部通过。
3. 检查点人工审阅发现固定临时文件名会相互覆盖；先加入遗留同名文件的 RED 用例，
   再改为唯一临时文件。该用例现在通过。

最终运行结果：

```text
/bin/bash plugins/spec-guard/hooks/test-sync-map-gitlab.sh
# 6 tests OK

/bin/bash plugins/spec-guard/hooks/test-gitlab-tracker-integrity.sh --selftest
# 6 tests OK; title-only and partial-marker recovery are rejected

/bin/bash plugins/spec-guard/hooks/test-audit-map-consistency.sh
# 35 tests OK
```

## 未宣称的范围

- 以上全部是受控 `glab` 桩和本地 Git fixture；尚不是指定 GitLab 15.3 实例的真实
  Issue 写入/中断恢复 E2E。
- `--paginate` 的实例级行为将在最终 release-evidence 模块以明确目标和副作用确认后
  验证；失败时只能收缩支持声明，不能把当前 stub 结果描述为远端通过。
- 本检查点没有引入工作区绑定、GitLab task next 选择、分布式 lease 或自动并行执行。
