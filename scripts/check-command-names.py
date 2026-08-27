#!/usr/bin/env python3
"""校验插件**给用户看的输出**里提到的斜杠命令都真实存在。

背景：v0.4.1 把文档里 22 处 `/planning` 改成了 `/plan`（Claude Code 读的是
`.claude/commands/plan.md`，不是 `commands/planning.toml`），但那次替换
只扫了 `*.md`，**shell 脚本一个没碰**。于是 `phase-guard.sh` 每轮仍然注入
「建议下一步: /planning …」，模型照着调就报 `Unknown skill`。

检查范围刻意限定在**会到达用户眼前**的三处：

    plugins/*/hooks/*.sh        hook 注入内容与安装脚本的提示
    plugins/*/templates/*.md    写进用户项目 CLAUDE.md 的声明块
    plugins/*/commands/*.md     slash 命令自身的指令

`docs/` 与 `CHANGELOG.md` **不查** —— 它们要能讨论「`/planning` 是错的」
这件事本身，查了反而没法记录历史。

`hooks/test-*.sh` 也**不查** —— 回归测试的输出只给跑测试的人看，而测试里必然
出现构造的假路径（`CLAUDE_PLUGIN_ROOT=/x/spec-guard/9.9.9`）。把它们纳进来
只会逼测试去迁就一个与自己无关的判据。
"""

import pathlib
import re
import sys

# ⚠️ 下面两个集合是**兜底快照**，只在读不到本机装着的上游时才用。
#    能读到就以**上游本人**为准（见 upstream_live()）—— 冻结清单在上游改名时
#    不会自己跟上，而那正是 0.4.1 那个 bug 的成因：文档写着一个已经不存在的
#    命令，检查器照样放行。
#    末次核对：2026-08-28，上游 0.6.7（commit 7829ffd）—— 与实际一致。

# 上游 addy-agent-skills 的命令。取自 `.claude/commands/*.md` 的**文件名** ——
# 不是 `commands/*.toml`：两套目录内容等价但文件名不同（`plan.md` vs
# `planning.toml`），**Claude Code 读的是前者**。搞错这个正是 0.5.2 那个 bug。
UPSTREAM = {
    "build", "code-simplify", "plan", "review", "ship", "spec", "test", "webperf",
}

# Claude Code 自带的命令（不属于任何插件）。模板/命令文里写安装步骤会用到。
BUILTIN = {
    "plugin", "reload-plugins", "config", "permissions", "hooks", "help", "clear",
}

# 上游的 skill 名（`skills/*/` 的目录名）。命令文里 `invoke <name>` 引用的是这些，
# 和斜杠命令是两个不同的命名空间 —— `/plan` 是命令，
# `planning-and-task-breakdown` 是 skill，二者都存在且不可互换。
UPSTREAM_SKILLS = {
    "api-and-interface-design", "browser-testing-with-devtools", "ci-cd-and-automation",
    "code-review-and-quality", "code-simplification", "context-engineering",
    "debugging-and-error-recovery", "deprecation-and-migration", "documentation-and-adrs",
    "doubt-driven-development", "frontend-ui-engineering", "git-workflow-and-versioning",
    "idea-refine", "incremental-implementation", "interview-me",
    "observability-and-instrumentation", "performance-optimization",
    "planning-and-task-breakdown", "security-and-hardening", "shipping-and-launch",
    "source-driven-development", "spec-driven-development", "test-driven-development",
    "using-agent-skills",
}

# 前面必须是行首、空白、引号、反引号或括号 —— 避免把路径 `/Users/...`
# 和 URL 里的片段当成命令。
# ⚠️ 引号必须在集合里：hook 里的写法是 `NEXT="/plan 为 …"`，
#    第一版漏了 `"` 导致这个 lint 抓不到它本该抓的那个 bug。
CMD = re.compile(r"""(?:^|[\s`'"(（])/([a-z][a-z0-9-]*)""")

SCOPES = ["hooks/*.sh", "templates/*.md", "commands/*.md"]


# `invoke <name>` / `Invoke the <name> skill` —— 命令文里引用 skill 的写法
SKILL_REF = re.compile(r"[Ii]nvoke\s+(?:the\s+)?[`']?([a-z][a-z0-9-]{4,})[`']?")


def upstream_live():
    """读本机装着的上游，返回 (命令集, skill 集)。读不到返回 (None, None)。

    判据不冻结，问上游本人 —— 装着的那份就在本地，没有理由去猜。
    `installed_plugins.json` 的 `installPath` 是权威来源：cache 目录下可能
    同时躺着几个版本目录（版本号一个、commit sha 一个），挑错了就会拿一份
    已经不在用的清单当真。
    """
    try:
        import json
        import os
        # 环境变量不是为了灵活，是**为了它自己能被测试** ——
        # 写死 $HOME 的话，「上游删掉了某个命令」这条反向用例只能靠改真实的
        # 用户配置来构造。同 check-readme-sync.py 那个 root 参数。
        reg = pathlib.Path(os.environ.get("SPEC_GUARD_UPSTREAM_REGISTRY") or
                           (pathlib.Path.home() / ".claude/plugins/installed_plugins.json"))
        d = json.loads(reg.read_text(encoding="utf-8"))
        path = next(v[0]["installPath"] for k, v in d.get("plugins", {}).items()
                    if "agent-skills" in k and v)
        root = pathlib.Path(path)
        # 命令取 `.claude/commands/*.md` 的**文件名**，不是 `commands/*.toml`：
        # 两套目录内容等价但文件名不同（plan.md vs planning.toml），
        # 而 Claude Code 读的是前者。搞错这个正是 0.5.2 那个 bug。
        cmds = {p.stem for p in (root / ".claude/commands").glob("*.md")}
        skills = {p.name for p in (root / "skills").iterdir() if p.is_dir()}
        return (cmds or None), (skills or None)
    except Exception:
        return None, None


def own_commands(root: pathlib.Path) -> set[str]:
    d = root / "commands"
    return {p.stem for p in d.glob("*.md")} if d.is_dir() else set()


def own_skills(root: pathlib.Path) -> set[str]:
    d = root / "skills"
    return {p.name for p in d.iterdir() if p.is_dir()} if d.is_dir() else set()


def main() -> int:
    ok = True
    checked = 0
    live_cmds, live_skills = upstream_live()
    if live_cmds is None:
        print("  ⏭  读不到本机装着的上游，退回兜底快照（不代表快照是最新的）")
    # 校验集取**并集**：上游新增的名字不该被判失败。
    # 危险的方向是**删名/改名** —— 快照里有、上游已经没有的，单独抓。
    gone_cmds = (UPSTREAM - live_cmds) if live_cmds else set()
    gone_skills = (UPSTREAM_SKILLS - live_skills) if live_skills else set()
    for plugin in sorted(pathlib.Path("plugins").glob("*/")):
        known = own_commands(plugin) | UPSTREAM | (live_cmds or set()) | BUILTIN
        known_skills = own_skills(plugin) | UPSTREAM_SKILLS | (live_skills or set())
        for scope in SCOPES:
            for path in sorted(plugin.glob(scope)):
                # 回归测试脚本不是「用户可见输出」—— 它们的输出只给跑测试的人看，
                # 而里面必然出现构造的假路径（如 CLAUDE_PLUGIN_ROOT=/x/spec-guard/9.9.9）。
                # 把它们纳进来只会逼测试去迁就一个与自己无关的判据。
                if path.name.startswith("test-"):
                    continue
                checked += 1
                for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                    for name in CMD.findall(line):
                        if name in gone_cmds:
                            print(f"  ❌ {path}:{lineno} /{name} 在兜底快照里，"
                                  f"但**本机装着的上游已经没有它了** —— 快照过期，"
                                  f"照这条走会报 Unknown command")
                            ok = False
                        elif name not in known:
                            print(f"  ❌ {path}:{lineno} 引用了不存在的命令 /{name}")
                            ok = False
                    # skill 与命令是两个命名空间，分开校验
                    for name in SKILL_REF.findall(line):
                        if name in {"skill", "these"}:
                            continue
                        if name in gone_skills:
                            print(f"  ❌ {path}:{lineno} skill `{name}` 在兜底快照里，"
                                  f"但**本机装着的上游已经没有它了** —— 快照过期")
                            ok = False
                        elif name not in known_skills:
                            print(f"  ❌ {path}:{lineno} 引用了不存在的 skill `{name}`")
                            ok = False
    if ok:
        src = "上游本人" if live_cmds else "兜底快照"
        print(f"  ✅ {checked} 个用户可见文件，引用的命令与 skill 全部存在（对照：{src}）")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
