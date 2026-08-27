#!/usr/bin/env python3
"""检查 bash 3.2（macOS 自带）会误解析的 `$VAR<多字节字符>` 写法。

bash 3.2 会把紧跟在 `$VAR` 后面的多字节字符（如全角括号「）」）的首字节
吃进变量名，配合 `set -u` 直接致命退出。hook 失败是静默的，所以这类 bug
在 macOS 上表现为「守卫突然不说话了」。写成 `${VAR}` 即可。

CI 只跑 Linux（bash 5，多字节安全）时看不到，故做成静态检查。
"""
import re
import sys

PAT = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]")

def main() -> int:
    if not sys.argv[1:]:
        print("  ❌ 没有传入任何文件 —— 这不是「没问题」，是「什么都没查」")
        return 1
    ok = True
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                m = PAT.search(line)
                if m:
                    var = m.group(0)[:-1]
                    print(f"  ❌ {path}:{lineno} {var} 后紧跟多字节字符，"
                          f"写成 {'${' + var[1:] + '}'}")
                    ok = False
    if ok:
        print("  ✅ 无 bash 3.2 多字节解析陷阱")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
