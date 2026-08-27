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

# 上游 addy-agent-skills 的命令（`.claude/commands/*.md` 的文件名，
# 不是 `commands/*.toml` —— 两套目录文件名不同，Claude Code 读前者）
UPSTREAM = {
    "build", "code-simplify", "plan", "review", "ship", "spec", "test", "webperf",
}

# 前面必须是行首、空白、引号、反引号或括号 —— 避免把路径 `/Users/...`
# 和 URL 里的片段当成命令。
# ⚠️ 引号必须在集合里：hook 里的写法是 `NEXT="/plan 为 …"`，
#    第一版漏了 `"` 导致这个 lint 抓不到它本该抓的那个 bug。
CMD = re.compile(r"""(?:^|[\s`'"(（])/([a-z][a-z0-9-]*)""")

SCOPES = ["hooks/*.sh", "templates/*.md", "commands/*.md"]


def own_commands(root: pathlib.Path) -> set[str]:
    d = root / "commands"
    return {p.stem for p in d.glob("*.md")} if d.is_dir() else set()


def main() -> int:
    ok = True
    checked = 0
    for plugin in sorted(pathlib.Path("plugins").glob("*/")):
        known = own_commands(plugin) | UPSTREAM
        for scope in SCOPES:
            for path in sorted(plugin.glob(scope)):
                checked += 1
                for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                    for name in CMD.findall(line):
                        if name not in known:
                            print(f"  ❌ {path}:{lineno} 引用了不存在的命令 /{name}")
                            ok = False
    if ok:
        print(f"  ✅ {checked} 个用户可见文件，引用的命令全部存在")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
