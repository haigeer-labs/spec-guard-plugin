# 端到端实跑记录

**这份文档里的所有输出都是真跑出来的**，不是照着文档编的。

| | |
|---|---|
| 日期 | 2026-08-26 |
| 目标仓库 | 个人 public 仓库（0 star / 0 watcher），`gh 2.98.0` |
| 模式 | `github`，`issueTypes: false`（个人仓库无 issue types，自动降级） |
| 上游 | `agent-skills` commit `5a5ea45` |
| 产物 | 6 个 issue，跑完后 `deleteIssue` 全部真删除，零残留 |

> **为什么要真跑**：0.2.0 的 CHANGELOG 里挂着一条「`spec-github-bridge` 的 gh 命令
> 未经端到端实测」。这次跑出来的结果证明这条限制不是形式主义 —— 它藏着一个
> **所有单元测试都抓不到的 bug**（见最后一节）。

---

## 1. `/setup-convention github`

```
═══ 前置检查 ═══
  ✅ python3
  ✅ git 仓库
  ✅ gh 2.98.0
  ✅ gh issue create 支持 --parent
  ✅ gh 已认证
  ✅ 远端是 GitHub
  ⚠️  <owner>/<repo> 不支持 issue types（组织级功能，个人仓库用不了）
       → 自动降级：省略 --type，改用层级本身区分 task
       → 层级(--parent)和依赖(--blocked-by)照常可用，实测已验证
       → 不用 label 模拟 type：label 无层级无依赖，筛选逻辑会全废

═══ 落地约定（模式：github）═══
  ✅ 目录 spec/ tasks/ .agent/
  ✅ CLAUDE.md 声明块（追加）
  ✅ .agent/state.json (tracker=github)
  ✅ spec/CAPABILITY-MAP.md（模板）

═══ 自检 ═══
  ✅ hook 正常，当前阶段：MAP_ONLY
```

用户原有的 `CLAUDE.md` 内容完整保留（声明块是**追加**，不是覆盖）。

## 2. 填能力图 → hook 报断链

填入 2 个模块（`theme-tokens`、`icon-registry`，后者依赖前者）并写好 spec 后：

```
当前阶段: **SPECED**

  - tracker: github
  - spec: 能力图=true, 模块 spec=2 份
  - git: 分支=main, 未提交=1

**检测到断链：**
  ⚠ 存在 todo.md，但本项目已声明外部 tracker —— 二者不能并存
  ⚠ spec 已存在但 .agent/state.json 里没有模块 issue —— 链路在此断开

建议下一步: /sync-map 把能力图和模块落成 issue
```

第一条断链抓的是**目标仓库里本来就有的 `todo.md`** —— 真实检出，不是演示数据。

## 3. `/sync-map`

```
Epic #81                 Initiative: 前端资产单一真源治理
  ├─ #82  theme-tokens
  └─ #83  icon-registry   (blocked-by #82)
```

`issueTypes: false`，所以全程**不带 `--type`**。层级用 `gh issue create --parent`，
依赖用 `gh issue edit --add-blocked-by`，两者在个人免费仓库上都可用。

## 4. `/planning`

```
#82 theme-tokens
  ├─ #84  盘点 10 个主题文件的映射块，产出重复清单
  ├─ #85  抽出单一色板真源模块              (blocked-by #84)
  └─ #86  Checkpoint: 删除任一主题变体…      (blocked-by #85)
```

`tasks/theme-tokens/plan.md` 写成 **issue 编号索引**，不是 checklist：

```markdown
> Tasks tracked in GitHub Issues #82

## Task List
### Phase 1: 盘点
- #84 盘点 10 个主题文件的映射块，产出重复清单
### Phase 2: 收敛
- #85 抽出单一色板真源模块（blocked by #84）
### Checkpoint
- #86 Checkpoint: 删除任一主题变体，其余渲染不变（blocked by #85）
```

## 5. `/next` —— 依赖过滤

这是整条链路里唯一「确定性」的部分，也是最该被验证的：

```
2) 逐个查 blocked-by，跳过被阻塞的：
     #84 ✅ 无未关闭阻塞 → 可执行
     #85 ⛔ blocked by #84 → 跳过
     #86 ⛔ blocked by #85 → 跳过

3) 取第一个可执行的并认领：
     ✅ #84 已 assign @me
```

## 6. `/build` —— 状态机推进

切到 `chore/84-theme-token-inventory` 后：

| 时点 | 阶段 | 建议 |
|---|---|---|
| 有未提交改动 | `BUILDING` | `/test 验证 → /deliver 开 PR（有 1 处未提交改动）` |
| 已提交 | `TASK_READY` | `/deliver 开 PR（Closes #84）` |

## 7. `/verify-artifacts`

```
── E. GitHub 层 ──
  ✅ Epic #81 的模块 issue 数与能力图一致（2）
  ✅ issue #82 正文是摘要而非 spec 全文
```

同时在目标仓库里抓到 **6 个真实存在的 `tasks/*/todo.md`** 和一个 `tasks/plan.md` ——
都是该仓库原有的，声明 github tracker 后它们确实构成冲突。真检出。

## 8. `/deliver` —— **本次未跑**

`gh pr create` 是标准命令、无特殊参数，而 **PR 在 GitHub 上删不掉，只能关闭**。
跑一次会在目标仓库留下永久记录，收益（只验证 `verify-artifacts` 里
「PR 正文含 `Closes #n`」这一条检查）与代价不成比例。

**仍未经实测的部分**：`verify-artifacts` 的 PR 检查、以及「PR 合并自动关闭 issue」
这一环（后者是 GitHub 既有行为，非本插件逻辑）。

## 9. 清理

```
分支          从未推送，远端无痕
issue #81-#86  deleteIssue 真删除（不是关闭），残留检查 0 个
仓库设置       全程未改动
原有 issue     完好
```

---

## 这次跑出来的 bug

**`gh issue list --parent` 这个 flag 根本不存在。** `--parent` 只在
`gh issue create` 上。`gh issue list` 有 `parent` / `subIssues` 这两个
**`--json` 字段**，但没有同名 flag —— 极易混淆。

它被用在四个地方：

| 位置 | 后果 |
|---|---|
| `phase-guard.sh:101` | **GitHub 层从来没跑过**，每次静默落进「gh 不可用，降级判定」 |
| `verify-artifacts.sh` | Epic ↔ 能力图交叉校验永远 skip |
| `SKILL.md` 操作三 | `/next` 取任务命令直接 `unknown flag` |
| `CLAUDE.md` 模板 + README | 使用者照抄照错 |

**为什么单元测试抓不到**：12 个 phase-guard 断言全部跑在**没有 GitHub 的临时仓库**里，
降级分支正是那里的预期行为 —— 测试恰好覆盖了假象。**只有真连 GitHub 才暴露得出来。**

修复前后：

```
修复前  当前阶段: PLANNED (gh 不可用，降级判定)      ← gh 明明完全可用
修复后  当前阶段: TASK_CLAIMED
        - GitHub: 3 个未关闭 task, 已认领 #84 盘点 10 个主题文件的映射块
        ⚠ 已认领 #84 但当前分支 [main] 不含 issue 号 —— 可能在错误分支上工作
```

正确写法是 REST sub-issues 端点（`{owner}` / `{repo}` 占位符自动解析，仓库外干净失败）：

```bash
gh api "repos/{owner}/{repo}/issues/<module-issue>/sub_issues"
gh api "repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by"
```

⚠️ REST 返回**所有状态**，不像 `gh issue list` 有 `--state`，要自己筛 `state == "open"`。

---

## 教训

**「装了没报错」不等于「跑通了」。** 这个 bug 存在期间，hook 每次都正常输出、
从不报错、测试全绿 —— 它只是安静地少做了一整层工作，而降级文案还把原因
归给了「网络或权限」。

对应到 `CLAUDE.md` 的三条铁律：第 2 条「探测失败就降级，不误报」是对的，
但**降级本身必须是可观察的**。一个永远在降级的探测器，和一个坏掉的探测器
没有区别。
