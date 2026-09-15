#!/usr/bin/env python3
"""README 内嵌的声明块必须与 templates/ 逐字节一致。

README 里内嵌模板是**刻意的** —— 不跑 `/setup-convention` 的人（以及 agent）
要能直接照着复制。代价是第二份真相源，而这个项目自己反复在说
「两份真相源必然分叉」。

这个校验就是那份代价的对冲：分叉当场报错。

补它的直接原因：0.5.x → 0.7.0 之间 README 内嵌的是一份 106 行的旧版模板，
含早已废弃的 task 级 PR 约定，**连续三个版本没人发现**。
"""
import pathlib
import re
import sys

# 默认是仓库根；接受一个可选参数指向别处 —— 这不是为了灵活，
# 是为了**这个校验器自己能被测试**（见 scripts/test-checkers.sh）。
# 写死 __file__ 的话，反向用例只能靠改真仓库的文件来构造，那比不测还糟。
ROOT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
TPL = ROOT / "plugins/spec-guard/templates"

MARK_B = "<!-- BEGIN:agent-skills-convention -->"
MARK_E = "<!-- END:agent-skills-convention -->"

FAIL = 0


def bad(msg: str) -> None:
    global FAIL
    print(f"  ❌ {msg}")
    FAIL = 1


text = README.read_text(encoding="utf-8")

for name in ("claude-block-local",):
    src = TPL / f"{name}.md"
    if not src.exists():
        bad(f"模板缺失: {src.relative_to(ROOT)}")
        continue

    # README 里用 <!-- SYNC:<name> BEGIN/END --> 圈出内嵌区，区内是一个 ```` 围栏
    m = re.search(
        rf"<!-- SYNC:{re.escape(name)} BEGIN -->\n(.*?)\n<!-- SYNC:{re.escape(name)} END -->",
        text,
        re.S,
    )
    if not m:
        bad(f"README 里找不到 SYNC:{name} 标记对")
        continue

    fence = re.match(r"````+\w*\n(.*)\n````+\s*$", m.group(1), re.S)
    if not fence:
        bad(f"SYNC:{name} 区内不是一个完整的代码围栏")
        continue

    want = f"{MARK_B}\n{src.read_text(encoding='utf-8').rstrip()}\n{MARK_E}"
    got = fence.group(1).rstrip("\n")
    if got == want:
        print(f"  ✅ README 内嵌的 {name} 与模板一致（{len(want.splitlines())} 行）")
    else:
        bad(
            f"README 内嵌的 {name} 与 templates/{name}.md 分叉了 "
            f"（README {len(got.splitlines())} 行 / 模板 {len(want.splitlines())} 行）"
        )
        print("     改了模板就要同步 README —— 内嵌是刻意的，分叉不是。")

sys.exit(FAIL)
