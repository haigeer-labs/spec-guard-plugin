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
"""

import pathlib
import re
import sys

# ⚠️ 下面两个集合是**手工维护的快照**，上游改名它们不会自己跟上。
#    改上游版本时按 docs/upstream-analysis.md 的「重新核对清单」重验。
#    末次核对：2026-08-27，上游 commit 5a5ea45。

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


def own_commands(root: pathlib.Path) -> set[str]:
    d = root / "commands"
    return {p.stem for p in d.glob("*.md")} if d.is_dir() else set()


def own_skills(root: pathlib.Path) -> set[str]:
    d = root / "skills"
    return {p.name for p in d.iterdir() if p.is_dir()} if d.is_dir() else set()


def main() -> int:
    ok = True
    checked = 0
    for plugin in sorted(pathlib.Path("plugins").glob("*/")):
        known = own_commands(plugin) | UPSTREAM | BUILTIN
        known_skills = own_skills(plugin) | UPSTREAM_SKILLS
        for scope in SCOPES:
            for path in sorted(plugin.glob(scope)):
                checked += 1
                for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                    for name in CMD.findall(line):
                        if name not in known:
                            print(f"  ❌ {path}:{lineno} 引用了不存在的命令 /{name}")
                            ok = False
                    # skill 与命令是两个命名空间，分开校验
                    for name in SKILL_REF.findall(line):
                        if name in {"skill", "these"}:
                            continue
                        if name not in known_skills:
                            print(f"  ❌ {path}:{lineno} 引用了不存在的 skill `{name}`")
                            ok = False
    if ok:
        print(f"  ✅ {checked} 个用户可见文件，引用的命令与 skill 全部存在")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
