# audit-safety-containment 增量验证记录

状态：PARTIAL。不是整个模块通过，不代表实验写入口已禁用。

## 2026-09-05：映射与 T1 / Issue #144

- 基线：`c2f247ce5b76fe87887206b0761ef8d16a17ea98`；本地分支 codex/fix/audit-safety-containment。
- GitHub：initiative #138 的子模块为 #139–#143，module #139 的任务为 #144–#157。REST sub_issues 与逐项 blocked_by 核验数量、顺序和依赖全部一致。
- `.agent/state.json` 与能力图 digest check：ok=true，5/5，missing/extra/rowsStale 为空，goalStale=false。
- T1 仅修改三个测试脚本并新增测试专用夹具；没有改生产运行时或指纹算法，没有启动真实 Agent。

### 测试证据

1. 修改前三套 ledger/worktree/CLI 回归全部退出 0。
2. RED：CLI 测试切换到独立 fixture 接口后，因 test_parallel_fixture 尚未实现而退出 1；这是新接口缺失，不声称复现了生产缺陷。
3. GREEN：实现 fixture 后，三套回归全部退出 0。worktree fixture 对缺失目录、错误 branch 和错误 HEAD 的反向输入均拒绝。
4. `/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh`：129 通过 / 0 失败。
5. `/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh`：72 通过 / 0 失败。
6. `/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh`：10 通过 / 0 失败。
7. `/bin/bash evals/codex-plugin-smoke.sh --selftest`：退出 0，正确区分通过、行为失败和环境未就绪；不等于真实宿主 E2E。
8. `/bin/bash scripts/validate.sh`：工作区首跑失败；test-checkers 会临时改 spec-digest.py，再用 Git 恢复，后者被沙箱拒绝。已只撤销该测试注释，没有改算法。将相同测试差异与新增 fixture 应用到独立本地 clone 后重跑退出 0。

独立 clone 与完整 validate 日志位于 `/private/tmp/spec-guard-containment.RZ9G4D`，日志文件 `validate.log`。该路径是本机临时证据，可能被清理；本记录保存结果摘要，后续模块交付还需最终版本的持久化验收证据。

### 剩余边界

生产 create/claim/provision/start/register/reclaim 仍未禁用；其原有行为断言按计划保留，待对应任务变更契约。只读场景的夹具已可独立构造，生产创建行为测试尚须调用生产入口。

没有向默认分支合并或发布，Issue #144 应在模块交付合并后才由提交 closing keyword 关闭。后续从 #145 继续，不把 T1 计为 F01–F04/F09/F10 已缓解。
