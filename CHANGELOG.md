# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.7.15] - 2026-08-28

体检续：这轮盯的是「任务落库」这一步。它是 skill 四个操作里**唯一没有命令
触发**的一个，也因此是唯一**完全没有产物校验**的一个。
查出来的第一条是这整轮体检里危害最大的。

### 修复

- **一个 task 都没做的模块会被宣告完成。**

  `phase-guard` 此前把「未关闭 task 数 = 0」一律判成 `MODULE_DONE`，
  并建议「推进到下一个模块」。可是那个 0 有两种成因：

  - 建过 N 条、全部关闭 → 模块真做完了
  - **一条都没建过** → 任务从没落库

  两者在那个计数上长得一模一样。实测复现：

  ```
  当前阶段: MODULE_DONE
    - plan: tasks/identity/plan.md=true
    - GitHub: 0 个未关闭 task
  建议下一步: /next 推进到下一个模块（[identity] 已无未关闭任务）
  ```

  plan.md 写着两个任务，GitHub 上一条 sub-issue 都没有，模块被判完成。

  **这是假完成，比假断链更难发现** —— 假断链会招来抱怨，
  假完成长得就像成功，还主动把你推向下一个模块。

  分开两者的信号一直在手里：REST `sub_issues` 返回**所有状态**，
  总数是现成的。现在 `总数 == 0` 判 `PLANNED (任务未落库)` 并报断链，
  指向 skill 的「操作二：任务落库」。事实行也带上了总数。

  > **为什么会漏到这一步**：skill 的操作一/三/四 分别由 `/sync-map`、
  > `/next`、`/deliver` 点名，**操作二没有任何命令、模板或文档引用它**。
  > `/plan` 跑完就没有下一步指路，而 phase-guard 又把这个状态当成了成功。

- **任务落库跟操作一一样会在中途失败后重建。** plan.md 的 Task List 原先是
  「全部建完再一次性回写」。0.7.13 刚给操作一修过同一件事，**操作二没跟上** ——
  又一次「修法只落了一边」，而这次是上一版的作者（我）留下的。
  一个模块建 N 条 issue，中途失败的窗口比操作一还大。
  改成每建成一条立刻把编号写进 Task List，重跑时跳过已有编号的。
  另补一句：用 `--blocked-by` 时建的顺序要让前置先出生。

### 新增

- **`verify-artifacts` 补上任务落库的产物校验**：模块 issue 的 sub-issue 数
  ↔ plan.md 的 `- #<n>` 索引条数。SKILL 的 Verification 里一直写着这条，
  但没有任何东西真去比。它一次盖住两种失败：

  | plan 索引 | sub-issue | 判定 |
  |---|---|---|
  | N > 0 | 0 | ❌ 任务从没落库 |
  | N | M ≠ N | ⚠️ 对不上（落库中途失败重跑的残留？或 plan.md 没回写全） |
  | 0 | M > 0 | ⚠️ plan.md 没写编号，跨会话续接找不到任务 |
  | N | N | ✅ |

  读不到 sub-issue 时 `skip`，不发绿灯也不判失败。

  这补上了 0.7.13 记的那条已知限制的一半：**task 级**的重跑残留现在查得出来，
  Epic 级的仍然查不出（那要跨 Epic 搜索，不在现有判据的形状里）。

### 测试

断言 93 → **99**（phase-guard 62 → 64，verify-artifacts 31 → 35），
含「建过且全部关闭仍要判 MODULE_DONE」和「数一致时放行」两条正向对照 ——
新判据不能变成新的误报源。

`docs/lenses.md` 加 A5：**「零」有两种成因，判据分不开就会报假完成。**
同类形状：grep 没匹配（模式错了还是真没有）、目录为空（清理干净还是没生成）、
diff 为空（没改动还是比错了对象）。

## [0.7.14] - 2026-08-28

体检续：这轮把 skill 里那些**每次 `/next` 都要跑的 gh 命令**拿去对着真 gh
和真仓库跑了一遍。一个硬失败的 bug，一处能砍掉 N 次 API 调用的多余步骤，
一条无从判断的筛选规则。

### 修复

- **`/next` 的「取到后」那条命令每次都会硬失败。**

  操作三写的是：

      gh issue view <n> --json title,body,parent,dependencies

  而 `dependencies` **不是合法字段**（真名叫 `blockedBy`）：

      Unknown JSON field: "dependencies"

  跟陷阱表里那条「`gh issue list --parent` 那个 flag 不存在」是**同一个形状**，
  只是这次躺在正文的操作步骤里。已改成 `blockedBy`（实测通过字段校验）。

### 变更

- **筛选被阻塞任务不再逐个 task 打 API。** 操作三原先要求对每个 task 单独跑
  `gh api .../dependencies/blocked_by`。但 REST `sub_issues` 的每一条里
  已经带了 `issue_dependencies_summary.blocked_by`，数的正好是**未关闭**的
  阻塞者：

  ```
  #11  open  {"blocked_by": 0, "total_blocked_by": 1, ...}   ← 前置 #10 已关闭
  #13  open  {"blocked_by": 1, "total_blocked_by": 1, ...}   ← 前置 #12 仍 open
  ```

  （在 `sentinel-livelab` 上逐条核对过。）一个 9 task 的模块因此省掉 9 次
  round trip，也去掉了一个「模型可能漏查几条」的循环。
  需要知道**是谁**在挡的时候才单独查那一个。

- **删掉筛选规则「排除 `issueType != Task`」。** REST `sub_issues` 的响应里
  根本没有 type 字段，这条规则在那份数据上无从判断；而 `--parent <module>`
  返回的按构造就是 task，skill 自己也写着它「本来就是冗余的」。
  把一条**评估不了**的规则放在有序筛选的第一位，只会逼模型去猜或多打 N 次 API。

  > 核对边界：本账号只有个人仓库（`issueTypes` 不可用）。有 issue types 的
  > 组织仓库上那个字段会不会出现，**没验过** —— 但即使出现，冗余这一点不变。

- Verification 里的 `gh issue view <epic> --json subIssues` 补上取数方式：
  它返回的是 `{nodes, totalCount}` 对象，不是裸数组，直接 `| length` 会得到 `2`。

### 新增

- **`scripts/check-gh-json-fields.py`** —— 校验仓库里写到的
  `gh <issue|pr|repo> view --json <字段>` 都真实存在。

  这个仓库已经**两次**把不存在的东西写进操作步骤，两次都是每跑必败、
  两次都在文档里躺了很久。跟其他 `check-*.py` 不同的是，
  **它的判据不是冻结清单，是问 gh 本人** —— 跑一次
  `gh issue view 1 --json <乱写>` 让 gh 吐出合法字段表。
  实测这一步 gh 在**本地**完成：不需要仓库上下文、不需要网络、不需要登录
  （`GH_HOST` 指向不存在的主机也照常打印）。gh 不可用时干净跳过并声明
  「跳过不代表通过」。

  它当场抓到了上面那个 `dependencies`。

### 测试

`test-checkers.sh` 14 → **17**（含「gh 不可用时干净跳过」的降级用例）。
接进 `validate.sh`，现在每次校验 13 个字段引用。

## [0.7.13] - 2026-08-27

体检续：这轮查的是**四个模型驱动、零测试的命令**（`/sync-map` `/next`
`/deliver` `/phase`）。三处问题，形状相同 ——
**不可逆操作没钉死「作用于什么」，也没记录「做到哪了」。**

### 修复

- **`/setup-convention` 和 `/teardown-convention` 的作用目录跟着 cwd 跑。**

  两个脚本都直接在当前工作目录上动手，而 Bash 的工作目录在会话里会被
  `cd` 改掉。从子目录跑时：

  - setup 把 `spec/ tasks/ .agent/` 和声明块建进**子目录** ——
    项目里于是有两套约定，而 hook 只认根上那套，装了等于没装
  - teardown 去删子目录里并不存在的块，报「什么都没做」退 2，
    根上的约定原封不动 —— **移除报成功却没移除**

  两处都改成先解析项目根再 `cd`，并把作用目录打印出来：

      ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

- **`/phase` 和 `/verify-artifacts` 从子目录跑会报假的「没装约定」。**

  两条命令都写着 `CLAUDE_PROJECT_DIR=$(pwd)`。从子目录跑时 hook 找不到
  CLAUDE.md，静默退 0（`verify-artifacts` 则退 2），命令于是报
  「本项目没有启用 spec-guard 约定，先跑 `/setup-convention`」。

  **假警报本身已经违反第一条不变量，它还会引出一次破坏性操作** ——
  用户照着提示跑 setup，就触发了上面那条。

- **`/sync-map` 中途失败后重跑会建出一套重复的 Epic 和模块 issue。**

  原步骤是「建 Epic → 建 N 个模块 issue → 建依赖 → **最后**写
  `.agent/state.json`」。而这一步在 GitHub 上做不可逆写入，且会中途失败：
  网络、限流、`--type` 在个人仓库上被拒（陷阱表里那条「孤儿 issue」说的就是它）、
  用户按停。任何一次都留下「GitHub 建了 k 个 / `state.json` 干干净净」，
  而 `/sync-map` 的前置判据读的正是 `initiative.issue` —— 它是空的，
  于是重跑从头再来一遍。

  改成**每建成一个 issue 就立刻写回 state.json**，重跑因此可续：
  `initiative.issue` 有值跳过建 Epic，`modules.<id>.issue` 有值跳过该模块。

  > 重复的 issue 可以 `gh issue delete` 删（我上一版说过「删不掉」，那是错的），
  > 但要先人工分辨哪套是哪套，依赖关系和 sub-issue 层级还得重连。

### 测试

断言 91 → **93**：子目录里跑 setup / teardown 必须仍作用于项目根。

### 没做什么

**没有把 `/sync-map` 脚本化。** 它要解析能力图、判断 issue types 可用性、
按依赖表连边，确定性执行的收益还不足以抵掉一个 200 行脚本的维护面 ——
这次治的是它那个具体的重复建 issue 缺陷，不是它的形态。

### 已知限制

- **`verify-artifacts` 查不出重复 Epic。** 它比对的是 `state.json` 指向的
  那个 Epic 的 sub-issue 数与能力图模块数；一次失败重跑残留的**另一套** Epic
  在这个判据之外，所以体检会全绿。上面的增量写回是在**防止**它发生，
  不是在**检测**它。已经发生过的只能人工用 `gh issue list` 对一遍。
- **`/sync-map` 仍是模型驱动，没有回归测试。** 本次只改了它的过程约定。

## [0.7.12] - 2026-08-27

一次整体体检，五处实测复现的 bug。三处是**同一个 0.7.11 的修法只落了一边**，
另两处是**没挣来的绿灯**。

### 修复

- **`phase-guard` 也有 0.7.11 那个「模块 id 带数字」的 bug —— 而且它每轮都跑。**

  0.7.11 修 `verify-artifacts` 时在文件顶部写下「重叠项的判定规则必须两边一致」，
  但只修了那一边。`phase-guard` 的判定顺序是反的：先从分支名捡数字，
  捡到了就不判模块。于是 `feat/oauth2` 里的 `2` 让模块分支判定整条失效：

  ```
  当前阶段: TASK_READY            ← 实际在模块分支上
  建议下一步: /deliver 开 PR（Closes #2）
  ```

  `#2` 是从分支名里捡的，跟这个模块毫无关系；而且它在模块分支上劝你开
  task PR，正是 0.6.0 要治的那件事。同一条分支、同一份 state.json，
  两个脚本结论相反。

  现在两边一律**先判模块、判不中才捡号**。老约定的 task 分支不受影响。

- **本地模式永远够不到「刻意空闲」豁免。**

  `activeModule` 为空的豁免（c37fe46 加的）排在 tracker 分支**之后**，
  而 `tracker=none` 在它前面就把控制流截走了。结果：

  ```
  ⚠ 有 spec 但没有 tasks//plan.md —— 链路在此断开
  建议下一步: /plan 为 [] 拆解任务
  ```

  路径里那个双斜杠和空的 `[]` 就是 `MODULE=""` 漏出来的。
  这不是边角料：本地模式**没有任何命令**负责给第一个模块设 `activeModule`
  （`/sync-map` 是 github 专属），所以它是本地模式跑完 `/spec` 的必经状态。

  豁免上移到所有 tracker 分支之前；「连 state.json 都没有」单独接住，
  不再把空模块名拼进任何路径。

- **`verify-artifacts` 在 gh 读不到 issue 正文时发绿灯。**

  E 段段头写着「探测失败就整段跳过，绝不误报」，同段另外三处（Epic /
  父 issue / PR 正文）失败时都老实 `skip`，只有正文体量比对是拿
  `wc -c` 数管道输出的：gh 失败 → 0 字节 → 落进 else → 打出
  「✅ 正文是摘要而非 spec 全文」。**把「没查成」算成「查过了没问题」，
  而这个脚本存在的意义就是不发这种绿灯。**

- **`teardown` 的自检会因为环境变量没设就整段跳过。**

  `HK="${CLAUDE_PLUGIN_ROOT:-}/hooks/phase-guard.sh"` 没有兜底，
  而 `setup-convention.sh` 一直有 `$HERE` 兜底。「实际跑一遍而不是让人
  相信一句话」是 0.7.9 把 teardown 改成脚本的**唯一理由**，它自己会
  退回成一句话。此前所有 teardown 用例都显式设了这个变量，所以三个版本没人发现。

- **`is_archived` 用了本仓明令禁止的 `cmd | grep -q`**（两个 hook 各一处）。

  `head -10 "$f" | grep -qiE '已归档|ARCHIVED'`：grep 命中即关管道，
  head 吃 SIGPIPE(141)，pipefail 传出 → 归档豁免失效 → 假违规。
  实测门槛是前 10 行约 256KB（真实 todo.md 到不了），**所以这条是卫生
  问题不是活 bug**。值得记的是 `verify-artifacts.sh` 里隔了 80 行就写着
  「herestring：管道 + grep -q 会 SIGPIPE」—— 同一个文件改了一处漏了另一处。

- `setup-convention` 在 `.disabled` 的 tracker 不符时提示「用 `gitlab` 模式重跑」，
  而本脚本只收 `github|local` —— 那个建议做不到。

### 新增

- **`scripts/check-grep-pipe.py`** —— 静态拦 `cmd | grep -q`。
  这条规则写在 CLAUDE.md 里，已经被违反三次（gh `--help`、`find todo.md`、
  `is_archived`），每次都是修一处漏一处。它的姊妹规则 `check-bash32`
  一直有检查器，这条没有。注释里提到该模式是允许的。

### 测试

断言 79 → **91**（`test-phase-guard` 52 → 60，`test-verify-artifacts` 27 → 31），
`test-checkers` 11 → 14。

两条老断言被**改了期望值**：`spec无issue(无remote→本地)` 和
`根目录SPEC(无remote→本地)` 断的正是上面那个 `tasks//plan.md`。
它们只比对「阶段|断链数」、从不看正文，所以那个畸形路径在 52 条断言底下
躺了很久 —— 新增的用例直接对正文做断言。

## [0.7.11] - 2026-08-27

### 修复

- **`verify-artifacts` 的分支检查从 0.6.0 起就留在 task 分支时代，会报假失败。**

  模块 id 自带数字时（`feat/oauth2`），分支名里的 `2` 被 `grep -oE '[0-9]+'`
  当成 task issue 号，于是：

  ```
  ❌ PR 正文没有 Closes #2 —— issue 不会自动关闭
  ```

  而 PR 正文里写的是**正确的** `Closes #5`（模块 issue）。
  **假失败，而「假断链比不报断链危害大得多」是本仓第一条不变量。**

  现在两边判定一致（末段整段相等）：模块分支比对**模块 issue**，
  并统计 `<base>..HEAD` 里带 closing keyword 的 commit 数；
  task 分支保持老规则。

  > **为什么漏了五个版本**：0.6.0 改约定时我判断「verify-artifacts 没有分支
  > 逻辑」——那次 grep 找的是 `BRANCH`，而这里那段变量叫 `BR` / `BRI`。
  > **一次失败的搜索被当成了「这里没有」。**
  > 已把这条补进 lens B1：「我搜过了，那边没有」不算数，判断某处不受影响要靠读。

- `commands/verify-artifacts.md` 两处过期：`/deliver` 前的检查项改成模块级；
  「三项重叠」里「分支 issue 号」改成「分支归属」并写明两边判定必须一致。

- 断言 76 → 79。

## [0.7.10] - 2026-08-27

### 修复

- **0.7.9 自己挖的坑：`setup-convention` 不认识 `state.json.disabled`。**

  teardown 把 `state.json` 改名保留（issue 编号映射删了找不回来）。但 setup
  只看 `state.json` 存不存在 —— 于是「teardown 之后改主意再 setup」会**静默
  建一个空的 state.json**，真正的映射孤零零躺在 `.disabled` 里。

  后果不只是丢数据：模型接着会看到「activeModule 没有对应 issue」→
  建议 `/sync-map` → **在 GitHub 上建出一套重复的 Epic 和模块 issue**。
  而 issue 在 GitHub 上删不掉。

  现在：tracker 一致就**自动恢复**（往返无损）；不一致就**既不恢复也不新建**，
  退非零并说明二选一，`.disabled` 原样保留。

  > 这条是 0.7.9 发布**二十分钟后**发现的，用的是 0.7.9 自己刚补进 lens B1 的
  > 那句话。已把它再推一层：**新增一个此前不存在的状态，也算改概念定义 ——
  > 刚发的改动同样要过这一遍。**

- `setup-convention` 落地阶段出现 ❌ 时会**明确退 1**，此前只打印不改退出码。

- 断言 74 → 76。

## [0.7.9] - 2026-08-27

### 修复

- **`/teardown-convention` 自 0.7.0 起就移除不干净，而且越修越黏。**

  0.7.0 给 hook 加了第二个激活信号 `.agent/state.json`（为 `--no-claude-md`
  零足迹模式）。而 teardown 明确**不删** state.json（里面有 issue 编号映射）——
  于是删完声明块，项目不是「约定被移除」，是**变成了零足迹模式**。

  0.7.5 之后更糟：hook 在零足迹模式下会每轮注入「先加载 `spec-github-bridge`」，
  **移除之后比移除之前更黏**。

  命令文里那句自我验证「无输出即为成功」也就成了假的 —— 实测输出如下：

  ```
  当前阶段: **MAP_ONLY**
  **本项目没有 CLAUDE.md 声明块（零足迹模式）。**
  动 spec、拆任务、取任务、交付之前，先加载 `spec-github-bridge` skill ——
  ```

  这是 lens B1（在一个配置下验证、全局发货）的一个变体：
  **改的不是配置，是「什么算激活」这个概念的定义 —— 而依赖这个概念的东西
  没被列出来重看。**

- **teardown 从模型驱动改成脚本。** 它是插件里**唯一的破坏性操作**
  （删用户 `CLAUDE.md` 里的内容），此前却完全靠模型按 `.md` 里的步骤做，
  零测试 —— 而本仓的规矩是「写文件是幂等性和安全性要求高的操作，
  不能有非确定性」。setup 早就是脚本，teardown 一直不是。

  新的 `hooks/teardown-convention.sh`：

  | 动作 | 说明 |
  |---|---|
  | 删标记之间的内容（含标记） | 标记外一个字节不动；连带收掉多余空行 |
  | `state.json` → `state.json.disabled` | **这一步才是真正的移除**；改名不删除，issue 映射改回原名即可恢复 |
  | 实际跑一遍 `phase-guard.sh` | 而不是让人相信「无输出即为成功」这句话 |

  `--dry-run` 零写入；`--keep-state` 保留原名（**hook 会继续激活**，
  只在确实想切到零足迹模式时用）；没装过的项目退 2。

- 断言 68 → 74（含「teardown 后 CLAUDE.md 逐字回到原样」「teardown 后 hook 真的静默」
  两条 —— 后者正是 0.7.0–0.7.8 一直失败却没人跑的那条）。

## [0.7.8] - 2026-08-27

### 修复

- **hook 崩溃和「未启用」长得一模一样。** `hooks.json` 的命令串结尾是 `|| true`，
  `phase-guard.sh` 非零退出被整个吞掉，宿主收到**空输出** —— 而空输出正是
  「这个项目没启用约定」的正常表现。

  这就是第一次实跑那条教训的另一面：*「一个永远在降级的探测器，和一个坏掉的
  探测器没有区别」* —— 对「崩掉的」同样成立，而且更隐蔽：降级至少还有文案。

  现在非零退出会注入一条合法 JSON 说明「不是未启用，是执行失败」并给出
  `bash -x` 的排查命令。**静默退 0 仍然静默**（有反向用例钉住）。

- **`emit()` 可能吐半截 JSON。** 原先是无条件 `printf` 拼 JSON，
  内嵌的 `python3` 一失败，命令替换就是空字符串，输出变成 `{"…":}`。
  宿主会拒绝整个 hook —— **而拒绝同样是静默的**：一样坏，但更难查。

  改成两条编码路径（jq → python3）都失败时**什么都不输出**。
  宁可静默，也不要形如 JSON 的垃圾。

- 断言 65 → 68。

### 顺带扫过、确认没问题的已知限制

按 0.7.7 那条判断（**「不支持」是限制，「给错指引」是 bug**）把剩下的已知限制
过了一遍：

- **`gh` ≥ 2.94.0** —— 拦得很扎实：`setup-convention` 既比版本号，又**实际验证
  `--parent` 参数存在**（防 PATH 里有第二个 gh），失败即阻塞、零写入。真限制。
- **多人协作无加锁** —— skill 的取任务规则里本来就排除了「已有 assignee 且不是
  自己」的 task，剩下的是同时认领的窄竞态。真限制。
- **Windows 需 WSL / Git Bash** —— 没有 bash 就连 `setup-convention` 也跑不起来，
  从 bash 内部无法自我告知。真限制，且无解。

## [0.7.7] - 2026-08-27

### 修复

- **声明了 `gitlab` / `jira` 的项目会收到 GitHub 专属建议。** 两条路径都在发生：

  | 情况 | 0.7.7 之前说什么 | 问题 |
  |---|---|---|
  | 有条目号 | `PLANNED (gh 不可用，降级判定)` / 「恢复 gh 后 `/next`」 | `gh` 不是不可用，是**跟这个项目无关**，修好了也没用 |
  | 缺条目号 | 「`/sync-map` 把能力图和模块落成 issue」 | 那个命令会去 `gh` 建 **GitHub** issue |

  跟 0.7.6 的零足迹注入是**同一个形状：tracker 盲**，只是换了条代码路径 ——
  非 GitHub tracker 此前从没走过自己的分支，一路掉进为 GitHub 写的兜底里。

  现在它们有独立分支：`SPECED (gitlab)` / `TRACKED (gitlab)` / `BUILDING (gitlab)` /
  `PLANNED (gitlab)`，建议改成「在 `<tracker>` 里认领下一个任务后 `/build`」，
  缺条目号时提示把号写进 `state.json` 而不是跑 `/sync-map`。

  > **「不支持」和「给错指引」是两回事**：前者是限制，写进已知限制就够了；
  > 后者是 bug。这条限制从 0.1 就写着，而它的**表现**错了一路没人看过 ——
  > 因为「已知限制」四个字会让人以为那块已经想过了。

- 断言 61 → 65（含一条反向用例：整份注入里不许出现 `/sync-map` 或「gh 不可用」）。

## [未发布]

### 新增

- **`evals/module-namespace.sh`** —— 验插件的**头号卖点**：
  README 问题①「多需求并行时产物互相覆盖」。

  这条从立项起就写在 README 第一段，是整个插件存在的理由，**从没被行为验证过**。
  单测只验了 hook 的状态机（文件在不在），没验模型拿到约定后**真的会不会**把
  产物放进 `tasks/<module-id>/`。

  挑 local 模式跑，因为它**没有 skill 兜底** —— 13 行的块就是全部约定，
  不 work 就是真不 work。github 模式的两条通路已由 `skill-deferral` 覆盖。

  **2026-08-27 首跑：**

  | | 产物落点 | 命名空间 | 根下单例 |
  |---|---|---|---|
  | 有约定 | `tasks/identity/{plan,todo}.md` | 2/2 | 0 |
  | 无约定 | `tasks/{plan,todo}.md` | 0/2 | **2** |

  对照组精确复现了 README ① 描述的那个 bug。卖点成立。

  判据是**文件系统**不是 transcript —— 模型可以把命名空间说得头头是道然后写进
  `tasks/plan.md`。**看它做了什么，不看它说了什么。**

  > 这次的对照组是「不装插件」的基线，不是我们也要发的另一个配置 ——
  > 所以「对照组表现差」在这里是卖点成立的证据，而不是像 0.7.6 那样的缺陷报告。
  > **两种对照组要分清**，分不清的代价 0.7.5→0.7.6 已经付过一次。

## [0.7.6] - 2026-08-27

### 修复

- **0.7.5 的零足迹注入是 tracker 盲的。** 它给**所有**没写声明块的项目注入
  「先加载 `spec-github-bridge`」—— 包括 `tracker: none` 的本地模式项目。
  而那个 skill 全篇是 `gh issue create` / `--parent` / `--blocked-by` / 模块级 PR，
  对一个压根没有 GitHub 的项目毫无意义，指过去只会让它去建根本不存在的 issue。

  **又一次「在一个配置下验证、全局发货」** —— 0.7.5 的实测只跑了 github 模式，
  本地模式一次没测。这正是 0.7.5 自己刚写下的那条教训（「对照组本身也是一个
  被测配置」）换个方向再现：**被跳过的那个配置，也是要发货的东西。**

  现在按 tracker 分支：github 指向 skill；其余告诉它「本地模式没有对应的 skill，
  把声明块写回去」。

- **`local --no-claude-md` 现在被拒（退出码 2，零写入）。** 这个组合装了等于没装，
  而且比没装更迷惑 —— hook 照常报状态，看着像在工作，实际目录约定无处可放。

- 断言 59 → 61。

### 顺带查过没问题的

- **本地模式模板瘦身没丢任何规则。** 逐条 diff 过 0.6.1 → 0.7.x：27 行压成 13 行，
  五条规则一条不少，还补上了「`/build` 只认三条路径、只有第三条通配」的理由。
  本地模式没有 skill 兜底，丢了就是真丢了，所以这条必须核对。

## [0.7.5] - 2026-08-27

### 修复

- **`--no-claude-md` 零足迹模式此前是残的。** 0.7.0 引入它时，已知限制写的是
  「模型对目录约定的感知晚一步，靠 hook 每轮兜底」。**兜不住** ——
  `evals/skill-deferral.sh` 的 B 组就是这个模式，实测结果：

  > hook 正常激活、状态照常注入，**模型全程没加载 `spec-github-bridge`**，
  > 转头按自己的想法设计表结构、问技术栈去了。

  原因很简单：**hook 注入的是「状态」，而让 skill 被加载的是那句「指令」。**
  0.7.0 把指令留在了声明块里，零足迹模式恰恰没有声明块。

  0.7.5 起 hook 在检测到「无声明块」时把触发指令补进注入内容。
  **只有零足迹项目付这几行的代价，写了声明块的项目一个字都不多**（有反向用例）。

  > 教训：**「另一个机制会兜住」是最容易想当然的一类论断** —— 它听起来像系统
  > 设计而不像假设，所以不会被当成待验证项。这条从 0.7.0 起挂在已知限制里，
  > 写的时候没验，一验就是反的。
  >
  > 更该记的是：**这个结论一直躺在数据里。** B 组的 transcript 早就跑出来了，
  > 当时只读出「声明块起作用了」，没读出「零足迹模式不work」——
  > 同一份数据回答了两个问题，而我只问了一个。

- 断言 57 → 59。

## [0.7.4] - 2026-08-27

### 修复

- **0.7.0 同时改了两个 hook 的激活判据，只给一个加了测试。** `verify-artifacts.sh`
  的「`.agent/state.json` 也算激活信号」这条**漏测了三个版本** —— 也就是说
  `--no-claude-md` 装出来的项目能不能跑 `/verify-artifacts`，一直没人验过。

  补三个断言：零足迹下生效、两个信号都没有时仍退 2（正向那条不能把闸门整个
  拆了）、以及**报「todo.md 与 tracker 并存」时必须同时给出归档豁免办法**。

  最后一条是行为不是措辞：0.7.0 把这条知识从常驻的 15 行 context 挪进了报错
  文案，文案没了的话使用者面对违规无从下手。

  纪律随之收紧：**两个 hook 共用的判据要在两边都加用例。**

- 断言 54 → 57。


### 新增

- **`scripts/test-checkers.sh`** —— 四个 `check-*.py` 的回归套件（11 个断言，
  已接进 `validate.sh`，免费）。每个校验器至少一正一反：喂已知坏输入必须非零
  退出，喂好输入必须零退出。

  **为什么需要它**：一轮之内出过**四次**「新加的防线自己有毛病」——
  `check-command-names` 漏双引号前缀（抓不到它本该抓的那个 bug）、
  `check-readme-sync` 第一版没跑反向用例、发版 sha 核对拿 `HEAD` 比（文档提交
  就误报）、evals 判分把 skill 名写死成裸名（把一次成功判成失败）。

  四次同一个形状：**判据写完没有当场用真实数据跑一遍。**
  「防线本身也要被测试」这条一直写在 `CLAUDE.md` 里，但它是句口号不是套件 ——
  靠人自觉，四次里零次做到。

  纪律随之收紧：**新增 `check-*.py` 必须同时往这个套件里加一正一反。**

  两个刻意的实现选择：

  - `check-readme-sync.py` 现在接受一个可选 root 参数。**不是为了灵活，是为了
    它自己能被测试** —— 写死 `__file__` 的话，反向用例只能靠改真仓库的文件来
    构造，那比不测还糟。
  - bash32 的坏样本在**运行时拼装**，不让 `$VAR）` 这个模式出现在测试脚本源码里。
    用「跳过 `test-*.sh`」的豁免也能过，但那会削掉真实覆盖 —— 测试脚本本身也得
    能在 bash 3.2 上跑。**判据管得太宽和管得太窄一样是缺陷**，这次选的是不放宽。

  还给 `check-command-names` 那条「不查 `hooks/test-*.sh`」的豁免补了正反用例 ——
  0.7.3 刚加的豁免，没有用例的话下次有人收紧范围会静默把它去掉。


- **`evals/skill-deferral.sh`** —— 验 0.7.0 那次瘦身赖以成立的假设：
  **15 行声明块 + 一句触发指令，模型真的会去加载 `spec-github-bridge` 吗？**

  这个假设从 0.7.0 起就在那儿，**一次都没验过** —— 而它不成立的话，那次瘦身
  等于把细则删了。本仓自己的规矩是「标了『没实测』之后就该去测」。

  做法是两个只差一个声明块的脚手架项目、同一句话、headless 跑，从
  stream-json 里看有没有 `Skill(spec-github-bridge)` 的 tool_use。

  **2026-08-27 首跑（n=1）：**

  | | 声明块 | 结果 |
  |---|---|---|
  | A | 15 行 | ✅ 第 8 个工具调用时加载了 skill |
  | B | 无 | ❌ 全程没加载，转而「靠 plan.md 推断」直接设计表结构、问技术栈 |

  两组都有 `.agent/state.json`（0.7.0 起它本身就是 hook 激活信号），
  所以差异**只来自声明块本身**。

  会花 token，**不接进 `validate.sh`**。`--scaffold-only` 是免费自检路径。

  > 判据第一版把 skill 名写死成裸名，而实际是 `spec-guard:spec-github-bridge`，
  > 把一次成功判成了失败 —— 本轮第四次「新加的防线自己有毛病」。已改成按末段比对。

  > `claude plugin eval` 才是第一方格式，但它 early access、本账号未开通
  > （`plugin eval is currently in early access`）。开通后应迁过去。

  未升版本：`evals/` 在 `plugins/spec-guard/` 之外，对使用者零影响。

## [0.7.3] - 2026-08-27

### 新增

- **hook 自报版本。** 每轮注入的事实里多一行 `spec-guard: v<version>`，
  开发副本（直接从仓库跑、没经过 `/plugin` 安装）显示「开发副本」。

  加它的直接原因：`claude plugin update` 之后要**重启**才生效，而「重启了没有 /
  现在跑的是哪一版」此前只能去翻 `~/.claude/plugins/cache/*/.in_use` 标记猜。

  > 实测背景：连发五个版本之后本机装着的仍是 0.5.2，而当时**两个版本目录都有
  > `.in_use`** —— 旧的是会话占着的，新的是刚装上的。靠这个标记根本分不清
  > 「正在跑的是哪个」。

  实现上从 `CLAUDE_PLUGIN_ROOT` 的末段取版本号（装出来的路径形如
  `.../spec-guard/0.7.3`），**纯参数展开、零 fork** —— 这个 hook 每轮都跑，
  预算是 <1s，不能为一行版本号去读文件或起子进程。
  `CLAUDE_PLUGIN_ROOT` 缺失时回落到 `BASH_SOURCE`。

- 断言 52 → 54：未安装时报「开发副本」、安装路径下解析出版本号。

  > 这两个断言不能直接 grep 原始输出：`emit()` 有 jq 和 python3 两条路径，
  > python3 那条会把中文转义成 `\uXXXX`，grep 中文字面量抓不到。必须解 JSON。
  > —— 又一个「测试测的是空气」的近失事故。

### 修复

- **`check-command-names.py` 的判据范围收窄，排除 `hooks/test-*.sh`。**
  它把测试里构造的假路径 `CLAUDE_PLUGIN_ROOT=/x/spec-guard/9.9.9` 当成了
  斜杠命令 `/x`，直接把 `validate.sh` 判红。

  这条判据的自我定位是「**会到达用户眼前**的输出」，而回归测试的输出只给跑测试
  的人看。把测试纳进来，只会逼测试去迁就一个与自己无关的判据 ——
  **判据管得太宽和管得太窄一样是缺陷。**

## [0.7.2] - 2026-08-27

### 修复

- **`docs/design.md` 里有一条现在是错的。** 「额外检测的三种违规」表第三行写着
  *认领了 issue 但分支不含 issue 号 → 大概率在错误分支上工作* —— 那正是 0.6.0
  修掉的那个假断链判据，而设计文档还把它当成正确行为记着。

  这比 README 过期严重：本仓 `CLAUDE.md` 明写「改动前先读 design.md」，
  一份带着已废弃结论的设计文档，会让后面每次改动都建在旧结论上。

  同批修的还有：对象模型表（task 完成 = commit，模块完成 = PR）、
  「三个问题三个答案」（拆成四个，commit 和 PR 各答一个）、
  状态机（补 `MODULE_READY` / 两个模块分支态 / `IDLE(无活跃模块)`）。

- **0.7.1 把实跑的 PR 数写成了 5 个，实际是 4 个**（#65 #67 #70 #72）。
  已在 README 更正，并补上可核对的证据：PR #70 合并于 `13:20:34Z`，
  它 `Closes` 的 issue #69 关闭于 `13:20:35Z`，`reason=COMPLETED`。

  （按本仓惯例不回头改已发布的 0.7.1 条目，在这里更正。）

### 新增

- **`docs/design.md` 决策 6：声明块只放事实，过程进 skill。** 把 0.7.0 那次
  瘦身的完整推理落进设计文档 —— 包括**排掉的两个方案**及其官方依据：
  `@path` import 不减 context（*imported files load at launch*）、
  `.claude/rules/` + `paths:` 在「读到匹配文件」时才触发而约束要更早生效。

  排掉的方案和采用的方案一样重要 —— 没记下来的话，下一个人会再想一遍 `@import`。

- **`docs/walkthrough.md` 第三次实跑。** 前两次的教训都是「插件对项目现状的假设
  错了」；这次不一样 —— **假设没错，是约定自己变了**。

  > 第三条教训:改约定、改状态机、加测试是一个原子操作。分开做的中间态是
  > 「新约定 + 旧检查器」—— 那个状态下工具在对着正确的行为报错。

  顺带记下「怕留痕不是不验证的理由」：`/deliver` 的实测被跳过是因为
  「PR 在 GitHub 上删不掉」，结果一条免责声明在功能可用之后还挂了三个版本。

### 已知限制（补充）

- `design.md` 的「每条结论对应上游源码行号」这条纪律，只覆盖**上游行为**部分。
  决策 6 引的是 Claude Code 官方 memory 文档（会变），没有行号可锚。

## [0.7.1] - 2026-08-27

### 修复

- **README 落后了三个版本，而且是以最难看的方式落后的。** 它把两份模板
  **逐字内嵌**在「手动安装」章节里 —— 那是第二份真相源，从 0.5.x 一路分叉到
  0.7.0 没人发现：README 里躺着一份 106 行的旧块，还写着早已废弃的
  `<type>/<issue-number>-<slug>` 和「每个 task 一个 PR」。

  这个项目自己反复在说「两份真相源必然分叉，而分叉的现象是……」。这次它发生在
  插件自己身上，分叉的还正是**新用户第一眼会照抄的那段**。

- **一条已经不成立的免责声明还挂着。** 已知限制 3 写着「`/deliver` 的 PR 环节
  未经端到端实测」，理由是「PR 在 GitHub 上删不掉」。0.6.0 之后它就不成立了 ——
  在 `sentinel-livelab` 上真跑了 5 个 PR，`gh pr create` → `Closes #n` →
  合入默认分支自动关 issue → 分支清理，全链路验证过。

  **过期的免责声明比过期文档更糟：它在劝退使用者用一个已经证明可用的功能。**

- 另外五处同步到 0.6.x / 0.7.0：激活条件（新增 `.agent/state.json`）、
  命令表（`--replace` / `--no-claude-md`）、`/deliver` 的粒度、典型流程
  （改成模块分支 + `/build auto` + 禁 squash）、行为差异表补「交付粒度」一行。

### 新增

- **`scripts/check-readme-sync.py`** —— 断言 README 内嵌的声明块与
  `templates/*.md` **逐字节一致**，已接入 `validate.sh`。

  内嵌是刻意保留的（不跑命令的人和 agent 要能直接照抄），所以对冲的办法不是
  删掉内嵌，而是让分叉当场报错。README 里用 `<!-- SYNC:<name> BEGIN/END -->`
  圈出内嵌区，校验器比对围栏内容与模板。

  > 按本仓「防线本身也要被测试」的规矩，验过反向用例：往模板里注入一行，
  > 校验器报「README 17 行 / 模板 18 行 分叉了」并退 1；移除后恢复绿。

### 已知限制（补充）

- `check-readme-sync.py` 只管**声明块**这一处内嵌。README 里其他从别处抄来的
  内容（上游 SKILL.md 引文、`state.json` 样例、能力图样例）仍然是手工同步的，
  没有守卫。

## [0.7.0] - 2026-08-27

### 变更（需要重跑 `/setup-convention --replace` 迁移）

- **CLAUDE.md 声明块从 106 行瘦到 15 行**（local 模式 27 → 13）。搬走的过程细则
  全部进了 `spec-github-bridge` skill（219 → 277 行）。

  起因是使用者的实测：接入后项目 CLAUDE.md 321 行，声明块占 108 行 = 34%。
  而官方对 CLAUDE.md 的原话是 **target under 200 lines per CLAUDE.md file.
  Longer files consume more context and reduce adherence.**

  查文档时排掉了一个看起来对的方案：**`@path` import 省不了行数**。官方明说
  splitting into imports *helps organization but doesn't reduce context, since
  imported files load at launch* —— 它只解决维护，不解决占用。

  正解是官方自己给的：*If an entry is a multi-step procedure or only matters for
  one part of the codebase, move it to a **skill** or a path-scoped rule instead.*
  那 106 行里绝大部分是过程，而插件本来就有一个 skill，内容还重复了一半。

  留在 CLAUDE.md 里的只有两样：**推导不出来的事实**（路径、tracker 类型、
  几条硬禁令）+ **一句触发指令**（动 spec/拆任务/取任务/交付之前先加载 skill）。
  触发指令不能省 —— skill 是按需加载的，不写死的话模型可能在没加载 skill 的
  情况下就把 `SPEC.md` 建到根目录了，而那正是这个块当初存在的理由。

  `.claude/rules/` + `paths:` 前缀作用域**没有采用**：它在 Claude 读到匹配文件时
  才触发，而「不要在根目录建 SPEC.md」恰恰要在还没读任何文件时就知道。

### 新增

- **`/setup-convention --replace`** —— 已存在的声明块就地升级到当前模板。
  只替换 `BEGIN`/`END` 之间，标记外一个字节不碰（有反向用例钉住）。
  没有它的话老用户没法迁移：原来遇到已存在的块是直接跳过的。
- **`/setup-convention --no-claude-md`** —— 完全不写声明块。
- **`.agent/state.json` 成为第二个激活信号。** 两个 hook 原先只认 CLAUDE.md 里的
  约定标题，现在「有标题」或「有 state.json」满足其一即可。这是上一条的配套：
  不写声明块的项目也得让 hook 认得出自己管的项目。`.agent/` 是本插件自己的目录，
  拿它当信号不会污染无关仓库 —— 「默认不生效」那条不变量仍然成立。

### 改进

- **把「归档豁免」这条知识挪进报错文案。** 原先它占声明块 15 行常驻 context，
  而它只在报「todo.md 与 tracker 并存」那一刻才有用。现在两个 hook 的报错里都
  带上「在前 10 行内写『已归档』即可豁免」—— **只在真报错时才花 context**。
  顺带发现 HTML 注释是免费的：官方原话 block-level HTML comments *are stripped
  before the content is injected into Claude's context*，所以 BEGIN/END 标记不计成本。

### 已知限制（补充）

- **`--no-claude-md` 模式下模型对目录约定的感知晚一步。** hook 挂在
  `UserPromptSubmit` 上，注入时机其实早于对话，但它注入的是**状态**不是**约定**；
  选这个模式的项目要么自己在别处写一句「动 spec/tasks 前先加载
  `spec-github-bridge`」，要么接受这一点。
- **`--replace` 认的是完整标记行**（`<!-- BEGIN:agent-skills-convention -->`）。
  手工改坏了标记（比如删掉 `<!-- -->`）的项目会被当成「没装过」而追加第二块。

## [0.6.1] - 2026-08-27

### 修复

- **0.6.0 给「禁止 squash」写了个错的理由。** 原话是「squash 把 N 条 message
  压成一条，只有最后一个 issue 会关，其余留在 open」—— 这条是从机制推的
  （0.6.0 的已知限制里标了「没实测」），推错了。

  实查了仓库设置：GitHub 的 squash 默认是
  `squash_merge_commit_message: COMMIT_MESSAGES`，**会把每条 commit message
  拼进压缩后的正文**，那些 `Closes #n` 通常还在、照样生效。

  规矩本身不变，理由换成真的那两条：

  1. 那个拼接依赖一个**可改的仓库设置**（换成 `PR_BODY` 就全丢），合并对话框里的
     正文也随时能手改 —— 拿它当保证等于把 issue 状态挂在一个没人盯着的开关上
  2. `/build auto` 刻意做到一个 task 一条 commit，为的是**任意一点都能干净回滚**；
     squash 压成一条后这个性质当场消失，出事只能整个模块一起 revert

  第 2 条才是硬理由 —— 它跟仓库设置无关，改不掉。

  > 教训：把「没实测」标出来是对的，但标了之后就该去测。这条本来一句
  > `gh api repos/{owner}/{repo} --jq .squash_merge_commit_message` 就能验。

### 已知限制（更正）

- 0.6.0 的「squash 合并没有实测」一条**作废** —— 已查明默认行为。
  仍未实测的是：把 `squash_merge_commit_message` 改成 `PR_BODY` 之后
  closing keyword 是否真的全丢（按字面推断是，没跑过）。

## [0.6.0] - 2026-08-27

### 变更（约定层，会影响已落地的项目）

- **PR 粒度从 task 提到 module。** 原先是「一个 task 一条分支一个 PR」，
  现在是「一个模块一条分支一个 PR，每个 task 一条带 `Closes #n` 的 commit」。

  起因是使用者的实跑反馈：任务拆得细，于是每推进一个 task 就要停下来开 PR、
  等合并，**一个需求被切成 N 个互不相干的合并事件**，连贯性没了。

  查了下这个成本买到了什么 —— 在那个项目上：main 没有分支保护、
  `allow_auto_merge` 是 false、CI 是 `on: push` 也跑、最近 10 个 PR
  从开到合中位数 1 分 20 秒且全是 1 commit、开合是同一个人。也就是说
  PR 既不是评审关口也不是 CI 关口也不是保护关口，唯一买到的是
  `Closes #n` 那条追溯链接 —— 而那条链接，模块级 PR 一样给。

  **上游从来没要求过一个 task 一个 PR。** agent-skills 的 `/build` 到 commit
  为止，`/build auto` 是一路 commit 跑完整个 plan；task 级 PR 是本插件
  0.2.0 自己加的，这次把它收回去。

- **合并策略从此有硬约束：只能 merge commit 或 rebase，不能 squash。**
  task issue 靠 commit message 里的 closing keyword 关闭（官方原话：the issue
  will be closed when you merge the commit into the **default branch**），
  squash 把 N 条 message 压成一条，只有最后一个 issue 会关，其余留在 open，
  而 `/next` 会把它们当成没做完、重新取出来做第二遍。

### 修复

- **模块分支会被报成假断链。** `phase-guard.sh` 的
  「已认领 X 但当前分支不含 issue 号」那条，遇到 `feat/<module-id>` 这种
  不含 issue 号的模块分支必然命中 —— 改约定不改状态机的话，每轮都在报。
  新增 `ON_MODULE_BRANCH` 判定，且是**末段整段匹配**而非子串包含：
  子串匹配下 module id 叫 `a` 时分支 `master` 会被当成模块分支（已加反向用例）。

### 新增

- `phase-guard.sh` 新增 `MODULE_READY` 阶段与 `TASKS_DONE_HERE` 计数。
  模块级 PR 下 task issue 要到合并才关，`OPEN_TASKS` 全程不减 ——
  「这个模块做完没有」只能数 `<默认分支>..HEAD` 里的 closing keyword。
  这个数**只喂「建议下一步」，不进 `broken()`**：数偏了顶多建议早了，
  不会变成一条假断链。
- `/deliver` 开 PR 前先核对 task 覆盖，没覆盖齐就不开、报还差哪几个。
- 断言 40 → 45（`test-phase-guard.sh` 19 → 24，新增 5 条含 2 条反向用例）。

### 已知限制（补充）

- **`TASKS_DONE_HERE` 只认 `main`/`master` 作为基线分支。** 默认分支叫别的
  （`trunk`、`develop`）时它恒为 0，表现是 `MODULE_READY` 永远不出现、
  一直建议「继续取任务」。这是**保守失败**（不会误报断链），但会让人
  自己判断什么时候该开 PR。
- **squash 合并没有实测。** 官方文档只写了 commit message 的 closing keyword
  在合入默认分支时生效，没写 squash 时怎么处理被压掉的 message。
  上面「squash 会漏关 issue」是从机制推的，不是跑出来的 —— 所以约定写成
  「禁止 squash」而不是「squash 时要注意」。

## [0.5.2] - 2026-08-27

### 修复

- **P0：hook 每轮注入的「建议下一步」指向一个不存在的命令。**
  `phase-guard.sh` 三处、`setup-convention.sh` 两处、`verify-artifacts.sh` 一处
  仍写着 `/planning`，模型照着调就报 `Unknown skill: agent-skills:planning`。

  0.4.1 那次 `/planning` → `/plan` 的修复**只扫了 `*.md`**（用的
  `rglob('*.md')`），**shell 脚本一个都没碰** —— 而 `phase-guard.sh` 恰恰是
  每轮发言都注入的那个。一次不完整的替换，比不替换更隐蔽：文档全对了，
  真正到用户眼前的输出还是错的。

### 新增

- `scripts/check-command-names.py` —— 校验**用户可见输出**里提到的斜杠命令
  真实存在，已接入 `validate.sh`。检查范围刻意限定在会到达用户眼前的三处
  （`hooks/*.sh`、`templates/*.md`、`commands/*.md`）；`docs/` 与 CHANGELOG
  不查 —— 它们要能讨论「`/planning` 是错的」这件事本身。

  > 这个 lint 的第一版**漏了双引号前缀**，抓不到 `NEXT="/plan …"` 这种写法，
  > 也就抓不到它本该抓的那个 bug。加断言验证「注入坏名字要报错」之后才发现。
  > **防线本身也要被测试。**

  第二版补齐三处（用户追问「其他斜杠命令你也检查下」后全量审计出来的）：

  - **skill 名此前零覆盖** —— 命令文里的 `invoke <name>` 引用的是 skill，
    和斜杠命令是**两个命名空间**（`/plan` 是命令，`planning-and-task-breakdown`
    是 skill，都存在且不可互换）。现在分开校验。
  - **Claude Code 内建命令**（`/plugin`、`/reload-plugins` 等）加入允许集，
    避免模板里写安装步骤时误报。
  - 两个命名快照标注为**手工维护、会过期**，并接进
    `docs/upstream-analysis.md` 的重新核对清单第 7 条。

## [0.5.1] - 2026-08-26

### 修复

- **「项目在两个 initiative 之间」被误报为断链。** 状态机原先只看
  「有 spec 且无模块 issue」就报断链,不问是不是**刻意空闲**。一个上一批全部交付、
  下一批还没起的项目 —— 7 份 spec、issue 全关、没有在做的活 —— 每轮都被催
  「去把能力图落成 issue」。又是一次假断链。

  现在区分三种情况:

  | state.json | activeModule | 判定 |
  |---|---|---|
  | 存在 | 空 | `IDLE (无活跃模块)` —— **不报断链**,这是刻意声明的空闲 |
  | 存在 | 有值但无 issue | 真断链,文案指名 `activeModule=[x]` |
  | 不存在 | — | 真断链,文案说明是缺 state.json |

  断链文案也从笼统的「没有模块 issue」改为指名道姓,便于定位。

## [0.5.0] - 2026-08-26

### 新增

- **识别归档的任务清单，不再误报。** 检查器原先分不清「归档记录」和「活清单」——
  一个已完成模块的 `todo.md` 是**历史**，把它当成「与 tracker 并存」来报违规是误报。

  约定：文件**前 10 行**内出现 `已归档` 或 `ARCHIVED`（不区分大小写）即视为归档，
  从并存检查和命名空间检查里排除。限定前 10 行是刻意的 —— 只认头部声明，
  避免正文里偶然提到就被误判。

  在一个真实项目上验证：6 份归档 + 根下两份不再报违规，**只剩唯一活的那份被正确指出**。

  这补的是设计上的一个盲区：插件**假设你从零开始**。对已经长出自己体系的项目，
  它原先只会对着历史记录挑毛病 —— 而「假断链比不报断链危害大得多」。

### 已知限制（补充）

- **插件仍假设从零开始。** 约定块是「替换」而非「适配」——如果项目 `CLAUDE.md`
  里已有冲突的目录约定，`/setup-convention` 会**追加**出两套互相矛盾的指令，
  比覆盖更糟（agent 会看到两个冲突的真源）。落地前请先人工核对现有约定。

## [0.4.1] - 2026-08-26

### 修复

- **P0：`gh issue list --parent` 这个 flag 根本不存在。** `--parent` 只在
  `gh issue create` 上；`gh issue list` 有 `parent` / `subIssues` 这两个
  **`--json` 字段**，但没有同名 flag。四处受影响：

  | 位置 | 后果 |
  |---|---|
  | `phase-guard.sh:101` | **GitHub 层从来没跑过**，每次静默落进「gh 不可用，降级判定」 |
  | `verify-artifacts.sh` | Epic ↔ 能力图交叉校验永远 skip |
  | `SKILL.md` 操作三 | `/next` 取任务命令直接 `unknown flag` |
  | `CLAUDE.md` 模板 + README | 使用者照抄照错 |

  全部改用 REST sub-issues 端点
  （`gh api "repos/{owner}/{repo}/issues/<n>/sub_issues"`，`{owner}`/`{repo}`
  占位符自动解析，仓库外干净失败）。REST 返回**所有状态**，已补 `state == "open"` 筛选。

  **12 个 phase-guard 断言全绿却没抓到** —— 它们跑在没有 GitHub 的临时仓库里，
  降级分支正是那里的预期行为，测试恰好覆盖了假象。只有真连 GitHub 才暴露得出来。

- **文档里 22 处命令名写错**：上游的拆解命令在 Claude Code 里叫 **`/plan`**，不是
  `/planning`。上游有两套等价但文件名不同的命令目录 —— `commands/planning.toml`
  与 `.claude/commands/plan.md`，**Claude Code 读的是后者**。照着旧文档敲会得到
  「命令不存在」。（skill 目录名 `planning-and-task-breakdown` 未变，那些路径引用是对的。）

### 新增

- `docs/walkthrough.md` —— 端到端实跑记录。真实仓库、真实产物、真实输出：
  `/setup-convention` → `/sync-map` → `/plan` → `/next` → `/build` →
  `/verify-artifacts`，跑完 6 个 issue 全部 `deleteIssue` 真删除、零残留。

### 变更

- 已知限制 3 从「gh 命令未经端到端实测」收窄为「仅 `/deliver` 的 PR 环节未实测」

### 已知限制（补充）

- **降级必须可观察。** 三条铁律的第 2 条「探测失败就降级，不误报」是对的，
  但一个**永远在降级**的探测器和一个坏掉的探测器没有区别。目前没有机制
  区分「这次降级是对的」和「它一直在降级」。

## [0.4.0] - 2026-08-26

### 新增

- **github 模式自适应 issue types**，个人仓库不再被挡在门外。

  0.3.0 里 `/setup-convention github` 探测到没有 issue types 就**硬阻塞**。
  实测下来这个判断过重了 —— 三个 gh 参数的可用性并不一致：

  | gh 参数 | 依赖的 GitHub 功能 | 个人免费仓库实测 |
  |---|---|---|
  | `--type Feature/Task` | issue types | ❌ `type "Task" not found; available types:`（空） |
  | `--parent` | sub-issues | ✅ 层级建立成功，REST + GraphQL 双向确认 |
  | `--add-blocked-by` | issue dependencies | ✅ 依赖建立成功 |

  **只有 issue types 是组织级的**（GitHub 员工在 community#175785 的原话：
  *available only for organizations ... not for personal repositories*）。
  而 `/next` 的第一条筛选规则「排除 `issueType != Task`」本来就冗余 ——
  模块 issue 的 sub-issue 按构造就是 task，层级已编码了这个身份。

  所以不新增 tracker 模式，改为让 `github` 模式自适应：`/setup-convention`
  探测一次，把结果写进 `.agent/state.json` 的 `issueTypes`，
  `spec-github-bridge` 据此决定加不加 `--type`。**流程一步不少**，
  只失去按 type 跨仓筛选的能力。

- `spec-github-bridge` 增加「issue types 可用性」章节和两条 Common Rationalizations

### 变更

- `/setup-convention github` 在个人仓库上从**阻塞**改为**降级 + 告知**

### 已知限制（补充）

- 硬加 `--type` 会**留下孤儿 issue** —— gh 先把 issue 建出来再校验 type，
  失败时不回滚。实测确认。所以必须读 `state.json` 的 `issueTypes`，不要试错。
- 额度（官方文档）：sub-issue 每个父 issue **100 个**、嵌套 **8 层**、
  每种依赖关系 **50 个**。本插件只用到 3 层，远未触顶。

## [0.3.0] - 2026-08-26

### 新增

- **`/verify-artifacts`** —— 产物落地校验（只读）。`phase-guard` 回答「现在在哪个
  阶段」，它回答「已经落下的产物对不对」。整套约定从头到尾都是**提示词**，
  软指令必须配硬检测，否则跑歪了没人知道。覆盖 9 类检查：

  | 层 | 检查 |
  |---|---|
  | 能力图 | 模板占位符未填 / 评审未勾选 / module id 非 kebab-case |
  | spec | **文件名 ↔ 能力图 module id 比对** |
  | 目录 | 根目录 `SPEC*.md` / `tasks/` 缺命名空间 / `todo.md` 与 tracker 并存 |
  | plan | tracker 模式下仍是 checklist / 没写 tracker 位置 |
  | GitHub | Epic sub-issue 数 ≠ 模块数 / issue 正文粘贴 spec 全文 / PR 缺 `Closes #n` / 分支 task 不属于 activeModule |

  其中 spec 文件名比对补的是最阴险的一类漂移：`phase-guard.sh:80` 只数
  `spec/*.md` 的**数量**，从不跟能力图比对 module id。能力图写 `identity`、
  模型建了 `spec/user-identity.md`，阶段照样往前推，下游全部静默错位。

- `setup-convention.sh` 增加 **issue types 可用性探测**。`--type Feature/Task`
  依赖 GitHub issue types，这是**组织级功能，个人仓库用不了**。原先只查 gh 版本
  和 `--parent` 参数存在性 —— 这两项在个人仓库上一样全绿，然后 `/sync-map`
  的第一条命令就炸。探测不到时降级为警告，绝不假阻塞。
- `test-verify-artifacts.sh` —— 16 个断言，含「合规项目零误报」和「local 模式的
  checkbox 不误报」两条反向用例

### 修复

- **P0：`setup-convention.sh` 的 github 前置检查有 40% 概率假阻塞。**
  `gh issue create --help | grep -q -- "--parent"` —— `grep -q` 命中即关管道，
  还在输出的 `gh` 吃到 SIGPIPE(141)，`set -o pipefail` 把它传出来，判断为假。
  **实测 30 次里 12 次假阻塞**，且错误信息是误导性的「跑 type -a gh 检查 PATH」。
  改 herestring 后 30/30 稳定。
- 同类问题全仓库扫出并修掉 5 处（`setup-convention.sh` ×2、`phase-guard.sh` ×1、
  `validate.sh` ×1、`test-phase-guard.sh` ×1）。其中 `phase-guard.sh:94` 的
  `find tasks -name todo.md | grep -q .` 会漏报「todo.md 与 tracker 并存」。
- CLAUDE.md 加了这条禁令，`/verify-artifacts` 的实现和测试都不用管道

### 已知限制（补充）

- github 模式需要**组织仓库**，个人仓库请用 local 模式
- `verify-artifacts` 的 GitHub 层仍未经端到端实测（缺可用的组织仓库）

## [0.2.1] - 2026-08-26

### 修复

- **P0：macOS 上 hook 静默崩溃。** `$VAR` 后紧跟全角括号（如
  `"…Closes #$BRANCH_ISSUE）"`）时，macOS 自带的 bash 3.2 会把该字符的首字节
  吃进变量名，配合 `set -u` 直接致命退出。共 7 处：

  | 文件 | 影响 |
  |---|---|
  | `phase-guard.sh` ×2 | 进入 `TASK_READY`（准备开 PR 那一刻）hook 就死，且 hook 失败是静默的 |
  | `setup-convention.sh` ×4 | local 模式安装无声失败，`CLAUDE.md` 声明块根本没写进去 |
  | `validate.sh` ×1 | 缺执行位时的提示语 |

  全部改为 `${VAR}`。

### 新增

- `scripts/check-bash32.py` —— 静态检查这一类多字节解析陷阱，已接入 `validate.sh`
- CI 加 macOS matrix 并显式用 `/bin/bash` —— 原先只跑 ubuntu（bash 5，多字节安全），
  所以这个 bug 在 CI 里永远是绿的

### 变更

- 模板里过期的「本块由 install.sh 生成」改为实际的 `/setup-convention`
- README / CLAUDE.md 的测试数量从「12 个场景」更正为 15 个断言
- **明确最低上游版本：commit `5a5ea45`（2026-08-21）。** 更早的版本里
  `spec-driven-development` 的 Phase 0 和 `planning-and-task-breakdown` 的
  Task List Target **根本不存在**（实测 `7829ffd` / 2026-07-26：175 个文件、
  两者全树 0 命中），本插件的五个缺口全部悬空、症状是「Phase 0 永远不触发」。
  已写进 README 依赖章节、`docs/design.md` 参考章节和 `docs/upstream-analysis.md` 顶部
- `docs/upstream-analysis.md` 按 commit `5a5ea45` 重新核对：**五个缺口一个都没被上游补掉**。
  补了结果表、逐条验证命令；修正行号漂移（Task List Target 155→150、三条约束 60-64→59-63）；
  注明上游 `hooks/` 目录新增了 `sdd-cache-*` / `simplify-ignore` 但**均未注册进 `hooks.json`**

## [0.2.0] - 2026-08-26

### 新增

- `hooks/setup-convention.sh` —— **确定性执行**的安装脚本，`/setup-convention`
  改为调用它而不是让 LLM 逐步解释。写文件的幂等性和安全性不能有非确定性。
- `--dry-run` 支持
- `/teardown-convention` —— 移除项目约定，保留用户的 spec/plan 内容
- 完整的手动安装章节（README），含可直接复制的 CLAUDE.md 声明块原文，
  AI agent 可不依赖命令自行完成安装
- setup 脚本的回归测试（dry-run 零写入 / 不覆盖用户内容 / 幂等）

### 修复

- 测试脚本在 `cd` 到临时目录后相对路径失效，导致误报

### 已知限制（补充）

- `spec-github-bridge` 里的 gh 命令未经端到端实测
- 已启用 + `gh` 网络调用的 hook 耗时未实测（无 gh 环境下为 ~154ms）
- 文案硬编码中文
- Windows 需 WSL 或 Git Bash

## [0.1.0] - 2026-08-26

首个版本。

### 新增

- `phase-guard.sh` —— UserPromptSubmit hook，注入链路状态并检测断链
  - 9 个阶段的状态机（IDLE / MAP_ONLY / SPECED / TRACKED / PLANNED / TASK_CLAIMED / BUILDING / TASK_READY / MODULE_DONE）
  - 三种 tracker 模式：`github` / `none` / `other`
  - `gh` 不可用时自动降级，不误报
  - 未声明约定的仓库静默退出
- `/setup-convention` —— 在项目中落地目录约定
- `/phase` —— 主动查询链路状态
- `/sync-map` `/next` `/deliver` —— GitHub Issue 流程命令
- `spec-github-bridge` skill —— 四个操作的完整流程
- 三份模板：GitHub 模式声明块、本地模式声明块、能力图

### 已知限制

- 任务层自动化只覆盖 `github` 和 `none` 两种模式，GitLab / Jira 仅检测到 plan 层
- 需要 `gh` ≥ 2.94.0（`--type` / `--parent` / `--blocked-by`）
