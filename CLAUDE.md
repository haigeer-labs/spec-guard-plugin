# CLAUDE.md

给在**本仓库**（spec-guard 插件本身）工作的 AI agent 用。

> ⚠️ **作用域**：本文件配置的是开发 spec-guard 这个插件的 agent。
> 它**不是**给使用者复制到自己项目里的——使用者要的是
> `plugins/spec-guard/templates/claude-block-*.md`，由 `/setup-convention` 写入。

> ⚠️ **自引用陷阱**：本文件刻意**不包含**那个会激活 phase-guard hook 的标题
> 字符串。如果在本仓库写入它，hook 会在插件自己的仓库上激活，报一堆无意义的断链。
> 修改本文件时不要粘贴 `templates/claude-block-github.md` 的内容。

---

## 这是什么

一个 Claude Code 插件，给 `addyosmani/agent-skills` 补三样东西：

1. 多模块 Spec 目录约定
2. GitHub Issue 打通
3. 链路断裂检测（UserPromptSubmit hook）

设计依据见 `docs/design.md`，**改动前先读它**——里面每条结论都对应上游源码的
具体行号，不是拍脑袋定的。

---

## 目录

```
.claude-plugin/marketplace.json         ← marketplace 清单（路径不能改）
plugins/spec-guard/
├── .claude-plugin/plugin.json          ← 插件清单（路径不能改）
├── commands/*.md                       ← slash 命令
├── hooks/
│   ├── hooks.json                      ← hook 注册
│   ├── phase-guard.sh                  ← 核心：状态探测（每轮跑，<1s）
│   ├── verify-artifacts.sh             ← 产物落地校验（按需跑，可打 gh）
│   └── test-*.sh                       ← 回归测试
├── skills/spec-github-bridge/SKILL.md
└── templates/                          ← 由 /setup-convention 写入用户项目
docs/design.md                          ← 需求与设计
scripts/
├── validate.sh                     ← 仓库完整性校验（下面几个 check 由它调）
└── check-*.py                      ← manifests / bash32 / 命令名 / README↔模板同步
```

---

## 改动前必读

### phase-guard.sh 的三条不可违反的性质

1. **默认不生效** —— 检查用户项目的 CLAUDE.md 是否含约定标题，没有就静默 `exit 0`。
   装了插件不能污染其他项目。
2. **探测失败就降级，不误报** —— `gh` 不可用、远端不是 GitHub、不是 git 仓库，
   任何一种都不能报假断链。**假断链比不报断链危害大得多。**
3. **不越权** —— 只注入事实和建议，断链处理必须「先说明、得到确认后再执行」。

改动时如果动摇了任何一条，先想清楚为什么。

### 无外部依赖

`phase-guard.sh` 只能依赖 `bash` / `git` / `python3`。
**不要引入 `jq` 硬依赖** —— 早期版本踩过，缺 `jq` 时 `activeModule` 静默读不出来，
一路误判。现在用 `jread()` 做 python3 兜底。

---

## 工作流

```bash
# 改完必跑这三个
/bin/bash scripts/validate.sh
/bin/bash plugins/spec-guard/hooks/test-phase-guard.sh
/bin/bash plugins/spec-guard/hooks/test-verify-artifacts.sh
```

**显式写 `/bin/bash`**，不要写 `bash` —— macOS 上后者可能是 Homebrew 的 5.x，
而 3.2 才是这个项目踩过坑的那个版本（见 CHANGELOG 0.2.1）。


改了 `phase-guard.sh` 的状态机逻辑，**必须同步加测试用例**。
当前 68 个断言：`test-phase-guard.sh` 44 个（各阶段 / 三种 tracker 模式 / 归档豁免 /
刻意空闲 / 模块级分支 / 静默退出 / 不崩溃 + setup-convention 11 个，含声明块行数上限、
零足迹激活、`--replace` 只动标记内、自报版本）、
`test-verify-artifacts.sh` 24 个（含「合规项目零误报」「归档不误报」「无标记仍报违规」
「零足迹激活」等反向用例）。

**两个 hook 共用的判据要在两边都加用例。** 0.7.0 同时改了 `phase-guard` 和
`verify-artifacts` 的激活判据，但只给前者加了测试，后者漏了三个版本。

模块分支那组测试**必须让 GitHub 层真跑起来**（测试里放了个 `gh` 桩）——
它测的断链只在 `GH_OK=true` 时才走得到，落进降级分支的话测的是空气。

**反向用例和正向一样重要** —— 这个项目修过的假断链比真 bug 多。

### 校验器自己也有回归套件

`scripts/test-checkers.sh`（11 个断言，已接进 `validate.sh`，免费）。
四个 `check-*.py` 每个至少一正一反：喂已知坏输入必须非零退出，喂好输入必须零退出。

**为什么单独有这一层**：一轮之内出过**四次**「新加的防线自己有毛病」——
`check-command-names` 漏双引号前缀、`check-readme-sync` 没跑反向用例、
发版 sha 核对拿 HEAD 比、evals 判分把 skill 名写死成裸名。
四次同一个形状：**判据写完没有当场用真实数据跑一遍**。

「防线本身也要被测试」这条一直写在这里，但它是句口号不是套件 ——
靠人自觉，四次里零次做到。**新增 `check-*.py` 必须同时往这个套件里加一正一反。**

> `check-readme-sync.py` 接受一个可选的 root 参数，那不是为了灵活，
> 是**为了它自己能被测试** —— 写死 `__file__` 的话反向用例只能靠改真仓库文件构造。

### 按需评测（会花 token，不在 validate 里）

```bash
/bin/bash evals/skill-deferral.sh --scaffold-only    # 免费:只建脚手架 + 查 hook 激活
/bin/bash evals/skill-deferral.sh                    # 真跑:判 skill 有没有被加载(github 模式两条通路)
/bin/bash evals/module-namespace.sh --scaffold-only  # 免费
/bin/bash evals/module-namespace.sh                  # 真跑:判产物有没有落进 tasks/<module>/(local 模式)
```

两个评测各管一个模式，加起来覆盖**我们发的四种配置**里有意义的三种
（`local + --no-claude-md` 已被禁）。

验的是 0.7.0 那次瘦身赖以成立的假设：**15 行的声明块 + 一句触发指令，模型真的
会去加载 `spec-github-bridge`**。不成立的话那次瘦身等于把细则删了。

两条通路**都必须**让 skill 被加载：A 组靠声明块里那句触发指令，
B 组（零足迹 / `--no-claude-md`）靠 hook 注入的那句。

**改 `templates/claude-block-github.md` 的触发指令、或改 hook 的零足迹注入，
就该重跑一次。**

`module-namespace` 验的是 README 问题①（多模块产物互相覆盖）——
**插件的头号卖点，从立项起没被行为验证过**。它的判据是**文件系统**不是
transcript：跑完看 `tasks/` 下的产物落在哪，比读模型说了什么客观。
2026-08-27 首跑：有约定 → `tasks/identity/{plan,todo}.md`（2/2）；
无约定 → `tasks/{plan,todo}.md`（根下单例 2）—— 对照组精确复现了要治的那个 bug。

2026-08-27：首跑（0.7.4）A 第 8 个工具调用加载、**B 全程没加载**；
0.7.5 给零足迹补上触发指令后复跑，**B 变成第 1 个工具调用就加载**。
判据据此从「A 加载 && B 不加载」改成「两组都加载」，并用旧数据做了反向回归。

> `claude plugin eval` 才是第一方格式，但它 early access、本账号未开通。
> 开通后应迁过去。

---

## 发版

```
1. 改 plugins/spec-guard/.claude-plugin/plugin.json 的 version
2. 更新 CHANGELOG.md（含「已知限制」章节）
3. bash scripts/validate.sh && bash plugins/spec-guard/hooks/test-phase-guard.sh
4. git tag v<version>
5. push
6. 拉一下自己装的那份，确认真的跟上了：

```bash
claude plugin marketplace update spec-guard-marketplace
claude plugin update spec-guard@spec-guard-marketplace   # 之后要重启才生效
```

**版本号不升，使用者收不到更新** —— Claude Code 靠 `plugin.json` 的 `version`
判断是否拉取新版。

**怎么知道重启后跑的是哪一版**：0.7.3 起 hook 每轮注入的事实里带一行
`spec-guard: v<version>`（开发副本显示「开发副本」）。在装了约定的项目里发一句话
就能看见 —— 不用再去翻 `~/.claude/plugins/cache/*/.in_use`。

**第 6 步不是多余的。** 2026-08-27 实测：连发 0.6.0 → 0.7.2 五个版本之后，
本机装着的仍然是 **0.5.2** —— 而那台机器上的目标项目 `CLAUDE.md` 已经是
0.7.x 的新约定。这正是 `docs/walkthrough.md` 第三次实跑那条教训说的
**「新约定 + 旧检查器」中间态**，只不过这次它是在插件作者自己的机器上，
而且**存在了整整五个版本没被发现**。

推得更远一点：`git push` 不是发版的终点，**「装着的那份跟仓库里的插件内容一致」
才是**。核对办法：

```bash
INST=$(python3 -c "import json,os;d=json.load(open(os.path.expanduser(
  '~/.claude/plugins/installed_plugins.json')));print(
  d['plugins']['spec-guard@spec-guard-marketplace'][0]['gitCommitSha'])")
git merge-base --is-ancestor "$INST" HEAD \
  && git diff --quiet "$INST" HEAD -- plugins/spec-guard \
  && echo "✅ 装着的就是当前插件内容" \
  || echo "⚠️  装着的落后了，跑上面两条 update"
```

**不要直接拿 `installed sha` 和 `git rev-parse HEAD` 比。** 只改 `CLAUDE.md` /
`docs/` 的提交会推进 HEAD 而不动插件内容 —— 那样比会得出「装着的落后了」的
**假警报**，而这个项目对假警报的态度写在三条不可违反的性质里。
判据要问的是「`plugins/spec-guard/` 有没有变」，不是「HEAD 有没有变」。

---

## 禁止

- **不要 fork 或 vendored 上游 agent-skills 的任何文件** —— 所有适配走约定和本插件
- **不要在 phase-guard.sh 里做写操作** —— 它是探测器，只读
- **不要在本仓库的 CLAUDE.md 里写激活字符串** —— 见顶部的自引用陷阱
- **不要用 `jq` 作为硬依赖**
- **不要写 `$VAR` 紧跟多字节字符** —— 如 `"…#$ISSUE）"`。macOS 自带 bash 3.2 会把
  全角括号的首字节吃进变量名，配上 `set -u` 直接致命退出，而 hook 失败是静默的。
  一律写 `${VAR}`。`scripts/check-bash32.py` 会拦，CI 也加了 macOS matrix
- **不要在 hook 里输出非 JSON** —— 宿主会拒绝，且失败是静默的
- **不要写 `cmd | grep -q`** —— `grep -q` 命中即关管道，还在输出的 `cmd` 吃到
  SIGPIPE(141)，`set -o pipefail` 把它传出来，判断永远为假。用 herestring
  （`grep -q pat <<<"$var"`）或纯 bash `case`
- **不要给 hook 加长耗时操作** —— 它在每次用户发言前跑，超过 1s 就会有体感

---

## 调试 hook

```bash
# 直接跑，看原始输出
CLAUDE_PROJECT_DIR=/path/to/test-project bash plugins/spec-guard/hooks/phase-guard.sh

# 解析出可读内容
CLAUDE_PROJECT_DIR=/path/to/test-project bash plugins/spec-guard/hooks/phase-guard.sh \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['hookSpecificOutput']['additionalContext'])"
```

**无输出**现在只剩一种可能：两个激活信号都不满足（正常）。
0.7.8 起脚本**非零退出会注入一条说明**而不是被 `hooks.json` 的 `|| true` 吞掉 ——
「没输出」和「崩了」以前长得一模一样，那正是第一次实跑那条教训说的形状。
