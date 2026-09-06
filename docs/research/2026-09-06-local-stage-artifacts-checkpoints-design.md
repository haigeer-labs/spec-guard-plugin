# 本地阶段识别、历史产物与检查点预告：调查和待确认设计

日期：2026-09-06。此报告保存首次调查证据。用户随后回复“继续”，已确认设计与本地实施范围；实施结果另见同目录实现记录。

## 边界和工作区

- 主 checkout：`/Users/vilin/Documents/gs/spec-guard-plugin`，`main@759f14321dd1b3933edaf86149a0d21894404c1f`，调查开始时干净。
- 本任务：`/Users/vilin/.codex/worktrees/68fd/spec-guard-plugin`，由同一提交的干净 detached worktree 建立 `codex/local-stage-artifact-checkpoint`。
- 其他 worktree：`/private/tmp/spec-guard-runtime-worker-manifest`，`codex/fix/runtime-worker-manifest@469c076`，调查开始时干净；未切换或修改。
- 保存分支 `codex/paused-controlled-parallel-20260906` 保留。仅用 `git archive/show` 读取 `886daf7`、`c0036fa`，未合并、cherry-pick 或恢复其 initiative。
- 没有启动额外代理、创建远端 Issue/PR、推送、发布、更新缓存、重启宿主或删除已有资源。临时夹具中的生命周期探针只作用于本轮创建的副本。
- 已读 AGENTS.md、CLAUDE.md、docs/design.md、docs/lenses.md、历史验证/工作流 spec、当前与安装版 GitHub bridge；使用 debugging、Git workflow、spec-driven-development skill。用户本轮的“先调查设计，确认后实施”优先于自动取任务/远端落库流程。

## 可复现方法

证据目录：`docs/research/local-stage-evidence-20260906/`。运行目录保留在 `/private/tmp/sg-stage-investigation-20260906/`。

`reproduce.py` 从候选提交的 `test_local_validation.py` 用 AST 提取原始 MAP 夹具；构造普通目录（无 `.git`），git/gh/glab 桩记录参数后退出 1。state 与用户提供的契约相同。对每个插件目录同时设置 `CLAUDE_PROJECT_DIR`、`PLUGIN_ROOT`、`PYTHONDONTWRITEBYTECODE=1` 和桩 PATH。每次运行保存 stdout、stderr、退出码与 CLI 调用。

重新构造时，从仓库根执行下面的 Python；它创建新的临时根并导出完整版本，不修改源码或安装缓存。安装目录是本次实际核实值，未来重跑应先重新核实。

```bash
python3 - <<'PY'
import io, pathlib, shutil, subprocess, tarfile, tempfile
root = pathlib.Path(tempfile.mkdtemp(prefix='sg-stage-repro-'))
evidence = pathlib.Path('docs/research/local-stage-evidence-20260906')
for name in ('reproduce.py', 'probes.py', 'regressions.py'):
    shutil.copy2(evidence / name, root / name)
for label, ref in [('baseline', '759f143'), ('candidate', '886daf7'), ('historical', 'c0036fa')]:
    target = root / label
    target.mkdir()
    paths = ['spec', 'tasks', '.agent'] if label == 'historical' else []
    archive = subprocess.check_output(['git', 'archive', ref, *paths])
    tarfile.open(fileobj=io.BytesIO(archive)).extractall(target)
subprocess.run(['python3', '-B', str(root / 'reproduce.py')], check=True)
subprocess.run(['python3', '-B', str(root / 'probes.py')], check=True)
print(root)
PY
```

直接重跑同一夹具的一个版本：

```bash
CLAUDE_PROJECT_DIR=/private/tmp/sg-stage-investigation-20260906/fixture \
PLUGIN_ROOT=/private/tmp/sg-stage-investigation-20260906/candidate/plugins/spec-guard \
PATH=/private/tmp/sg-stage-investigation-20260906/fixture/bin:"$PATH" \
SG_TEST_CALLS=/private/tmp/sg-stage-investigation-20260906/manual.calls \
PYTHONDONTWRITEBYTECODE=1 \
/bin/bash /private/tmp/sg-stage-investigation-20260906/candidate/plugins/spec-guard/hooks/phase-guard.sh
```

verify 替换最后的脚本名即可。要切换版本，必须同时改 `PLUGIN_ROOT` 和脚本绝对路径。探针最后将 fixture tracker 设为 gitlab；完整重跑 reproduce.py 会依次重建 github/gitlab 对照。

## A：阶段识别与空上下文是两件事

| 被测内容 | GitHub phase / exit | GitLab phase / exit | verify exit（两种 tracker） |
|---|---|---|---|
| main 基线 759f143 | SPECED / 0 | SPECED / 0 | 1 |
| 保存候选 886daf7 | LOCAL_VALIDATION / 0 | LOCAL_VALIDATION / 0 | 0 |
| Codex 安装缓存 0.8.0 | SPECED / 0 | SPECED / 0 | 0 |
| Claude 安装登记 0.7.51 | SPECED / 0 | SPECED / 0 | 0 |

基线实际正文：`activeModule=[alpha] 但 .agent/state.json 里没有它的 issue`，建议 `/spec-guard:sync-map`；verify 报 `worktree tracker binding 不可用（context-unknown）`。
候选实际正文：`LOCAL_VALIDATION (tracker 尚未激活)`、`活跃模块: alpha`；verify 明示 binding/远端投影/远端校验未执行，不代表通过。

所有 phase 在该夹具中均未调用 gh/glab。基线和安装版 verify 分别调用 `gh auth status` / `glab auth status` 桩；候选两种 tracker 的 phase/verify 都没有 gh/glab 调用。桩使所有这些调用不可能触达真实 tracker。

空上下文来源核实：

1. `hooks/setup-convention.sh:318` 创建安装初始 state：空 title、空 activeModule、issue=null、modules={}；已有 state 不覆盖，disabled state 优先恢复。这是初始化行为，不是 phase 写空 state。
2. GitHub bridge 操作一在远端模块创建后设置 activeModule；GitLab `gitlab_tracker.py:431` 同样在同步完成后更新。`/next` 在模块完成后推进它。
3. 保存候选定义了 local-validation 字段，但没有确定性的本地上下文写入入口；只修读取不能解决新项目仍为空。
4. `886daf7` 的 GitLab `sync_map()` 没有阶段守卫。直接脚本 probe 在合法本地 state 下仍调用 `glab auth status`，退出 1，报 `GitLab API 调用失败`，而不是阶段拒绝。这是候选未覆盖的门禁缺口。
5. 本地 state 的 lifecycle probe：pause 退出 0，checkpoint 中 alpha 的 spec/plan 均为 null，顶层 spec/plan 仍留着。原因是复制/清理遍历 state.modules，而记录模块遍历能力图。此模式不能直接宣称支持完整归档/恢复。

裁定：阶段误判是代码缺陷；空 state 是既有初始化契约与本地工作流入口缺失；候选可选择性复用，但不是完整修复。

## B：安装内容与运行内容必须分开

本次 `codex plugin list --available --json` 返回 installed=true、enabled=true、version=0.8.0，source.path 指向主 checkout 的 `plugins/spec-guard`；本会话实际 hook 注入的 spec-digest 路径却指向 Codex **缓存** 0.8.0。source.path 不能直接当作正在运行的目录。

Claude 的 `~/.claude/plugins/installed_plugins.json` 登记 user scope 0.7.51，路径为 `~/.claude/plugins/cache/spec-guard-marketplace/spec-guard/0.7.51`，gitCommitSha=`abb27872fe653fa415e1992aacf518004afbd118`。没有启动 Claude 会话，不能推断一个已经运行的 Claude 宿主加载了哪份内容。

完整插件文件逐项 SHA-256 对比（排除 pycache/pyc，包含新增、缺失和内容不同）：

| 对比 | 不同路径数 |
|---|---:|
| 基线 → 保存候选 | 11 |
| 基线 → Codex 缓存 | 60 |
| 候选 → Codex 缓存 | 62 |
| 基线 → Claude 安装目录 | 63 |
| 候选 → Claude 安装目录 | 65 |

详见 plugin-content.json，未用 HEAD 或版本字符串相等替代内容核验。安装版 verify 返回 0 是旧门禁较少且认证不可用时跳过的结果；其警告仍是“没写 Tasks tracked in ...”，不是本地阶段正确识别。

裁定：部署差异，不另造一个 B 代码 bug。本轮只证明候选部分行为正常与安装内容不同。安装更新成功、宿主重新加载生效均未验证，也未获操作授权。

## C：历史组合实测与 8 份归属

当前 main 没有活跃能力图和 state。将其产物复制到临时目录并保留约定激活标记，phase 显示 IDLE（已归档），verify 退出 0，报告“无能力图，跳过比对”。这不是历史六模块故障的当前复现。

| 临时组合 | 结果 |
|---|---|
| 当前已归档产物，无活跃图 | 基线/候选 verify 均 0，无图外模块错误 |
| c0036fa 六模块新图 + 全部原有顶层 spec | 基线/候选 verify 均 1；报同一组 8 个图外模块 |
| alpha 新图 + 相同历史产物 | 候选 verify 1，仍报这 8 个 |
| 上一组再加 orphan.md | 候选 verify 1，报原 8 个并包含 orphan |

`verify-history.sh` 对当前归档副本、c0036fa 副本都退出 0；这仅证明账本已记录文件的结构/摘要验证通过，不能证明未记录的 spec 内容。

| 顶层文件 | 历史归属 | 内容证据 |
|---|---|---|
| history-ledger.md | capability-history / completed / 20260903T074408Z-0001 | 顶层、归档文件、账本 SHA 三者相同 |
| history-migration.md | 同上 | 三者相同 |
| history-verification.md | 同上 | 三者相同 |
| history-workflow-integration.md | 同上 | 三者相同 |
| initiative-lifecycle.md | 同上 | 三者相同 |
| parallel-guidance.md | parallel-readiness-guidance / completed / 20260903T210029Z-0001 的能力图 | 图 SHA 有效；modules=[]、无 spec 快照；与归档提交 57eb28f 的顶层文件相同 |
| parallel-readiness.md | 同上 | 无 spec 快照；归档后在 167ea36 更新过，不能称内容已验证 |
| parallel-safety-gate.md | 同上 | 无 spec 快照；归档后在 167ea36 更新过，不能称内容已验证 |

历史代码核实：57eb28f 的 lifecycle 复制、记录、移除均遍历 state.modules；该 checkpoint 的 state 正是空 modules。旧能力图明确列出最后 3 个模块，故空映射导致历史记录不完整。现在的 lifecycle 已改成从图记录模块，但复制仍取 modules，probe 证实问题尚未完全消除。

裁定：至少 5 份是 verify 不识别可验证历史产物的误报；另 3 份是可证历史归属但缺少内容快照的遗留产物问题。不能批量删除，也不能把所有图外文件免检。

## D：共享交互规则的位置

现有入口分散：phase.md 只要求“建议下一步”；verify-artifacts.md 与 ops/verify 要求报错并确认修复；setup-convention.md 要求原样转述加提交提醒；sync-map.md 要求列出写入对象；next/deliver.md 和两个 bridge 分别定义停点。模板只声明路径和 skill 触发，没有统一的检查点契约。

建议唯一正文放 `plugins/spec-guard/references/workflow-checkpoints.md`。三个现有 skill（github bridge、gitlab bridge、ops）和阶段命令引用它；模板只加短触发引用，README 内嵌模板同步更新。上游 spec/plan/build/test 不 fork、不复制：由项目约定在这些阶段加载本插件共享规则，零说明块模式由 phase 的短路径/加载指引接入。检测器只报告事实，不能凭文件存在猜测已授权下一步。

规则要求在有意义的检查点说明：成果与验证、停止原因、具体确认项或无需确认、已获确认后的第一步及目标资源、下一停点。下一步必须根据本轮授权、实际产物和失败信息生成；不把检查点变成每个工具调用前的审批。

| 场景 | 应预告的实际第一步与下一停点 |
|---|---|
| 设计 → 计划 | 指明设计决策和拟落 plan 路径；确认后写计划，计划可评审时停 |
| 计划 → 实现 | 指明首个测试/实现文件和范围；按已有授权实施，越界决策/失败或约定验证节点停 |
| 实现 → 验证 | 指明测试命令、范围与环境；若验证已获授权直接运行，测试失败或验证完成停 |
| 验证失败 | 说明失败证据与影响；首步最小复现/定位；不得擅自降低标准，缺决策/修复验证完成停 |
| 交付前远端操作 | 展示仓库、分支、Issue/PR/MR 对象、写入内容；只执行已授权步骤，结果核实或未知时停 |
| 权限拒绝/结果未知 | 区分未执行与可能已执行；先只读核对，禁止盲目重试写入；核对完成或必须补授权时停 |
| 取消/暂停 | 保留成果，清楚说明没有排队继续；最近预告失效，下一步仅为明确提出的只读核对；普通“继续”不能恢复暂停 initiative |

## 最小设计与预计改动

建议三块独立能力，串行推进：`local-workflow-context` → `historical-artifact-consistency` → `workflow-checkpoint-preview`。B 是 A 的部署验收，不单建能力。此处仅提案，不落活跃能力图。

1. **A 读判据和写入口。** 选择性复用 local_validation.py、phase/verify 接入和聚焦测试；activeModule 始终单字符串，issue=null、modules={}。在现有 setup-convention 入口增加显式本地上下文参数（建议 `--local-validation --module=<id> --title=<title>`）；此分支不跑 tracker 预检，要求图/spec/plan 已就位，预览 state 差异后按用户授权原子写入。普通 setup 保持原行为，已有远端映射、disabled state 或不完整产物拒绝覆盖。两个 bridge 在本地计划完成后调用该入口，不再让模型手写空 state 或伪造 Issue。早于 plan 完成的阶段不宣称已进入 local-validation。
2. **A 门禁补全。** 字段存在时，未知/非法值也拒绝远端创建、刷新、绑定、取任务、交付；GitLab 确定性入口在客户端初始化前拒绝。退出本地阶段单独列出具体 tracker 激活操作并获授权，不让 sync-map 自动删字段。未声明字段沿用现有门禁。
3. **C 历史分类。** verify 的图外 spec 判断调用只读 helper，复用 capability-history 的 schema/路径/摘要验证和 capability_map 解析。先归当前图；再查已结束 initiative 的可验证 checkpoint。精确 spec 内容匹配标历史已验证；只有有效历史图归属但无 spec 内容证据则明确 WARN“历史归属可证，内容未验证”；真正无归属 FAIL。已有快照却内容不符、账本/引用损坏或路径越界不能落入宽松 WARN。无活跃图保持原兼容行为，不以历史豁免遗漏当前模块。
4. **C 生命周期接缝。** 对本地阶段从严格能力图选择要保存的实际 spec/plan，复制、记录、清理使用同一集合；先验证快照再处理当前文件。只修未来操作及测试，不整理本仓 8 份旧文件、不回写旧账本。实施前应以 pause/resume 反向用例确认没有证据遗漏；若无法保持现有安全语义，拒绝本地阶段生命周期写入并准确预告限制，不报假成功。
5. **D 共享规则和接入。** 一个参考正文、短入口引用、与路径/结果绑定的预告。无需新增 controller、worker、lease、授权账本或 worktree 协议。不把自然语言“继续”存成永久授权。

预计文件（相对 `plugins/spec-guard/`）：

| 范围 | 预计源码/规则文件 | 验证文件 |
|---|---|---|
| A | hooks/local_validation.py（复用）、phase-guard.sh、verify-artifacts.sh、workspace_binding.py、gitlab_tracker.py、setup-convention.sh；commands/setup-convention.md、bind-workspace.md、sync-map.md、next.md、deliver.md；三个现有 skill | test_local_validation.py；test-phase-guard.sh、test-verify-artifacts.sh；GitLab tracker/binding 回归；setup 正反用例 |
| C | hooks/verify-artifacts.sh；新增只读 hooks/artifact_history.py；hooks/initiative-lifecycle.sh；复用 capability-history.py，尽量不改账本实现 | 新增历史归属聚焦测试；test-history-verification.sh、test-initiative-lifecycle.sh |
| D | references/workflow-checkpoints.md（新增）；commands/phase.md、verify-artifacts.md、setup-convention.md、initiative-lifecycle.md 及 A 涉及命令；三个 skill；templates/claude-block-*.md、codex-block-*.md 的短触发规则 | adapter/模板回归；新增检查点场景与判决器自检；无需模型的引用检查不能冒充真实交互验收 |
| 文档/总验证 | docs/design.md、README.md、CHANGELOG.md、scripts/validate.sh；确认后新模块 spec/plan | 五项规定检查和与改动有关的专项回归 |

以上按职责估计，正式计划再将其拆成小步。不改安装缓存；不预定版本号、发布或安装命令的执行授权。

## 验收矩阵

| 项 | 正向 | 反向/兼容 |
|---|---|---|
| 本地上下文 | github/gitlab × phase/verify；显示单模块、tracker 未激活；CLI 记录无远端调用 | 非法 JSON/类型/阶段、空/错误模块、错图、缺 spec/plan、伪造映射拒绝；无字段保持旧门禁 |
| 创建/更新 state | 从明确模块及标题生成合法本地 state；幂等；预览不写；plan 后可跨会话读取 | 不覆盖已有映射/disabled state；输入非法不部分写；不执行认证/同步 |
| 远端入口 | 本地字段存在时所有直接及 skill 路径拒绝 | 不因旧 binding、伪造 issue、--confirm 越过；无字段旧流程回归 |
| 历史一致性 | 无活跃图兼容；新图与内容已验证旧 spec 共存；遗留图归属明确标未验证 | orphan、被改历史副本、坏 hash/路径/账本、历史同名当前模块不能豁免 |
| 生命周期 | 空远端映射也保存图中已有 spec/plan，pause/resume 往返一致 | 缺证据/复制失败不得假成功；不操作现有历史资料 |
| 安装验证 | 同一夹具、同包辅助文件、插件内容摘要；更新后和新宿主逐层验证 | verify exit 0、版本号相同、source.path 指向源码均不单独证明加载生效 |
| 检查点 | D 的七场景全部包含五项有实际内容的信息 | 已授权不重复审批；失败/未知不伪报成功；取消作废预告；“继续”不得恢复暂停并行功能 |

## 本轮验证记录与限制

详见证据目录 regressions.json、regression-transcripts.json。保存候选在隔离导出目录运行；这是候选评估，不是本任务修复完成。

- 重新执行 `python3 -B plugins/spec-guard/hooks/test_local_validation.py`：12 tests，OK（16.297s）。不是引用历史测试结论。
| 本轮候选检查 | 退出码 | 结果 |
|---|---:|---|
| `/bin/bash scripts/validate.sh` | 0 | 总校验通过，内部专项回归完成 |
| `/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh` | 0 | 134 通过 / 0 失败 |
| `/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh` | 0 | 73 通过 / 0 失败 |
| `/bin/bash plugins/spec-guard/hooks/test-codex-adapter.sh` | 0 | 10 通过 / 0 失败 |
| `/bin/bash evals/codex-plugin-smoke.sh --selftest` | 0 | 判决器的 0/1/2 三态自检通过，非真实宿主 smoke |

已有并行相关套件仅测试现有隔离/拒绝和只读行为，不启用执行器。
- 未运行：真实 Claude/Codex 模型交互 eval、真实宿主 smoke、真实 tracker 操作、安装更新/重启及发布验证。原因：本阶段无这些操作授权且安装内容不一致；自检不能代替真实宿主结果。
- 未运行全量 mutation-check：本轮未改源码；后续实现按实际变更选择变异回归，不让就地变异污染并行测试。
- 新的 state 写入口、历史分类、生命周期修复、检查点输出均尚未实现，因此对应验收暂未通过。

## 首次调查检查点（已由后续“继续”确认）

已完成：隔离复现 A/B/C、逐文件历史归属核实、D 入口定位、候选检查及最小设计。
停止原因：用户要求先审阅设计；本轮没有源码实施授权。
待确认：三块串行范围、显式本地 state 写入口、历史三分类（无快照仅 WARN 未验证）、生命周期接缝保护和共享检查点规则。
确认后的第一步：先将本设计整理为本任务自己的能力图、模块 spec 和正式本地 plan，展示首个测试/实现切片；不会导入暂停 initiative 的图/state。生成计划后先预告首个测试/实现切片，再按本次确认的范围实施，不重复索取同一授权。下一停止条件：完整验证结果可评审，或遇到超出设计的决策、权限拒绝、无法继续的验证失败。发布、推送、安装、宿主重启仍须在具体版本和操作列出后另获授权。
