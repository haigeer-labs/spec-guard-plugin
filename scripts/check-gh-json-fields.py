#!/usr/bin/env python3
"""校验仓库里写到的 `gh <sub> view --json <字段>` 都是真实存在的字段。

为什么要有它：这个仓库已经两次把不存在的东西写进操作步骤 ——
`gh issue list --parent`（那个 flag 只在 create 上），以及
`gh issue view --json dependencies`（真实字段叫 `blockedBy`）。
两次都是**每次跑都会硬失败**的命令，两次都在文档里躺了很久。

它跟 check-bash32 / check-grep-pipe 不同：**判据不是冻结的清单，是问 gh 本人**。
`gh <sub> view --json <乱写>` 会打印合法字段表，而且这一步是 gh **本地**做的 ——
不需要仓库上下文、不需要网络、不需要登录（实测 GH_HOST 指向不存在的主机也照常打印）。

gh 不可用时**干净跳过**并说明「跳过不代表通过」——
本仓的规矩是探测失败就降级，不假阻塞。
"""
import re
import shutil
import subprocess
import sys

USE = re.compile(r"gh\s+(issue|pr|repo)\s+view\b[^\n]*?--json\s+([A-Za-z][A-Za-z,]*)")


def valid_fields(sub: str):
    """问 gh 要 `gh <sub> view` 的合法字段表。拿不到就返回 None。"""
    # `gh issue view` 必须带一个编号才走到字段校验（不带的话先报
    # "accepts 1 arg(s), received 0"）。给个 1 即可 —— 字段校验在**取数据之前**，
    # 这个 issue 存不存在都不影响。
    argv = ["gh", sub, "view"] + (["1"] if sub in ("issue", "pr") else []) \
        + ["--json", "__probe__"]
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=15)
    except Exception:
        return None
    out = r.stdout + r.stderr
    if "Available fields:" not in out:
        return None
    tail = out.split("Available fields:", 1)[1]
    fields = {ln.strip() for ln in tail.splitlines() if ln.strip() and " " not in ln.strip()}
    return fields or None


def main() -> int:
    if shutil.which("gh") is None:
        print("  ⏭  gh 未安装，跳过 --json 字段校验（不代表通过）")
        return 0

    cache, ok, checked = {}, True, 0
    for path in sys.argv[1:]:
        try:
            text = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        for sub, fieldlist in USE.findall(text):
            if sub not in cache:
                cache[sub] = valid_fields(sub)
            known = cache[sub]
            if known is None:
                print(f"  ⏭  问不到 `gh {sub} view` 的字段表，跳过（不代表通过）")
                continue
            for f in [x for x in fieldlist.split(",") if x]:
                checked += 1
                if f not in known:
                    print(f"  ❌ {path}: `gh {sub} view --json {f}` —— 没有这个字段。"
                          f"合法值跑 `gh {sub} view --json x` 看")
                    ok = False
    if ok:
        print(f"  ✅ gh --json 字段全部存在（校验了 {checked} 个）")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
