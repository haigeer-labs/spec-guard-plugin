#!/usr/bin/env python3
"""检查 `cmd | grep -q` —— 本仓明令禁止的写法。

`grep -q` 命中即退出并关掉管道读端，还在写的上游命令吃到 SIGPIPE(141)，
`set -o pipefail` 把 141 传出来，判断因此永远为假。hook 失败是静默的，
所以这类 bug 表现为「守卫突然不说话了」或「豁免莫名其妙失效」。

改用 herestring：`grep -q pat <<<"$(cmd)"`，或纯 bash 的 `case`。

做成静态检查的原因：这条规则已经被违反三次（gh --help、find todo.md、
is_archived），每次都是修了一处、漏了另一处。CLAUDE.md 里写着它，
但写着不等于拦得住 —— check-bash32.py 是它的姊妹规则，一直有检查器。
"""
import re
import sys

# 只看管道右边紧跟的 grep -q/-qi/-qE… ；herestring 与 `grep -q pat file` 不涉及管道
PAT = re.compile(r"\|\s*grep\s+(-\w*q\w*\s|--quiet\b)")


def main() -> int:
    ok = True
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                if line.lstrip().startswith("#"):   # 注释里解释这个坑是允许的
                    continue
                if PAT.search(line):
                    print(f"  ❌ {path}:{lineno} `cmd | grep -q` 会因 SIGPIPE 永远判假，"
                          f"改用 herestring: grep -q pat <<<\"$(cmd)\"")
                    ok = False
    if ok:
        print("  ✅ 无 `cmd | grep -q` SIGPIPE 陷阱")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
