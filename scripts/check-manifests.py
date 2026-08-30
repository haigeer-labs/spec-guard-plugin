#!/usr/bin/env python3
"""校验 marketplace.json 和各 plugin.json 的一致性。"""
import json
import os
import sys


def load_manifest(src: str, host: str):
    manifest = os.path.join(src, f".{host}-plugin", "plugin.json")
    if not os.path.exists(manifest):
        return None
    return json.load(open(manifest, encoding="utf-8"))


def main() -> int:
    mf = ".claude-plugin/marketplace.json"
    if not os.path.exists(mf):
        print(f"  ❌ {mf} 不存在")
        return 1

    market = json.load(open(mf, encoding="utf-8"))
    plugins = market.get("plugins", [])
    if not plugins:
        print("  ❌ marketplace.json 里没有 plugins 条目")
        return 1

    ok = True
    for entry in plugins:
        name = entry.get("name", "(未命名)")
        src = entry.get("source", "").lstrip("./")
        manifest = os.path.join(src, ".claude-plugin", "plugin.json")

        pj = load_manifest(src, "claude")
        if pj is None:
            print(f"  ❌ {name}: source 指向的 {manifest} 不存在")
            ok = False
            continue

        if pj.get("name") != name:
            print(f"  ❌ 名称不一致: marketplace={name} plugin.json={pj.get('name')}")
            ok = False
            continue

        version = pj.get("version", "?")
        print(f"  ✅ {name} v{version}")

        codex = load_manifest(src, "codex")
        if codex is not None:
            if codex.get("name") != pj.get("name"):
                print(f"  ❌ Codex 名称不一致: Claude={pj.get('name')} Codex={codex.get('name')}")
                ok = False
            if codex.get("version") != pj.get("version"):
                print(f"  ❌ Codex 版本不一致: Claude={pj.get('version')} Codex={codex.get('version')}")
                ok = False
            if codex.get("skills") != "./skills/":
                print(f"  ❌ {name}: Codex skills 必须是 ./skills/")
                ok = False

            if codex.get("hooks") != "./hooks/hooks.json":
                print(f"  ❌ {name}: Codex hooks 必须是 ./hooks/hooks.json")
                ok = False

        # 目录存在性（有则校验，无则跳过——都是可选目录）
        for d in ("commands", "hooks", "skills", "agents"):
            path = os.path.join(src, d)
            if os.path.isdir(path) and not os.listdir(path):
                print(f"  ⚠️  {name}: {d}/ 是空目录")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
