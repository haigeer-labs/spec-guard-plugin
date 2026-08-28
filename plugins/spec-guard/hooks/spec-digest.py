#!/usr/bin/env python3
"""能力图 ↔ GitHub 投影的指纹：算它、比它。

**为什么是一个共用脚本，而不是各处内联。**
写指纹的是 `/sync-map`（模型执行），读指纹的是 `phase-guard` 和
`verify-artifacts` 两个 hook。同一个 hash 若各写各的实现，空白怎么归一、
反引号剥不剥、行怎么拼——只要有一处不同，算出来的 digest 就永远对不上，
表现是**一条关不掉的假警报**。这个仓库对假警报的态度写在三条不可违反的
性质里，所以算法必须只有一份。

一致性模型：
  spec/CAPABILITY-MAP.md  是唯一事实源
  GitHub issue            是它的投影
  .agent/state.json       记「上次投影时，能力图长什么样」

于是「本地改了、投影没跟上」变成纯本地的 hash 比对——不打 gh，
也不需要语义比对。

用法:
  spec-digest.py compute <map>            → 算出当前指纹（/sync-map 写回时用）
  spec-digest.py check   <map> <state>    → 比对，输出分歧（两个 hook 读）
  spec-digest.py --selftest               → 自检（已接进 validate.sh）

两个子命令都输出单行 JSON。任何异常都输出一个"什么都别报"的结构并退 0——
**探测失败就降级，不误报**。
"""
import hashlib
import json
import re
import sys

DIGEST_LEN = 12  # sha256 前 12 位十六进制。碰撞概率与「有人手改 state.json」同量级


def _h(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:DIGEST_LEN]


def _norm_lines(lines):
    """行尾空白剥掉、首尾空行去掉，再用 \\n 拼。

    只归一「肉眼看不见」的差异（CRLF、行尾空格、段落前后的空行）。
    实质内容改一个字就必须变——这条检测的全部意义在于抓到那种改动。
    """
    out = [ln.rstrip() for ln in lines]
    while out and not out[0]:
        out.pop(0)
    while out and not out[-1]:
        out.pop()
    return "\n".join(out)


def parse_map(path):
    """解析能力图。返回 (rows, goal_text)。

    rows: [(module_id, normalized_row_text), ...]，按文件里的顺序
    goal_text: `## 目标` 一节的正文；没有这一节时为 None
    """
    with open(path, encoding="utf-8") as f:
        raw = f.read().splitlines()

    rows = []
    for line in raw:
        if not line.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        first = cells[0]
        # 跳过表头和 |---|---| 分隔行
        if not first or first.lower() == "module id" or set(first) <= set("-: "):
            continue
        mid = first.strip("`")
        # 整行参与 digest（不只是 id）——职责或依赖改了也要能看出来。
        # 这同时补上了「删一个 + 加一个」和改名的盲区：只数个数看不出来。
        rows.append((mid, "|".join([mid] + cells[1:])))

    # `## 目标` 一节，读到下一个同级标题为止。
    # 没有这一节 → None → 目标段的指纹判定整个跳过（老能力图没这一节）。
    goal = None
    collecting = False
    buf = []
    for line in raw:
        if re.match(r"^##\s", line):
            if collecting:
                break
            if re.match(r"^##\s*(目标|Goal)\s*$", line.strip()):
                collecting = True
            continue
        if collecting:
            buf.append(line)
    if collecting:
        goal = _norm_lines(buf)

    return rows, goal


def compute(path):
    rows, goal = parse_map(path)
    return {
        "rows": [{"id": mid, "digest": _h(text)} for mid, text in rows],
        "order": [mid for mid, _ in rows],
        "goalDigest": _h(goal) if goal is not None else None,
        "placeholder": any(mid.startswith("example-") for mid, _ in rows),
    }


NOTHING = {
    "ok": False,
    "mapCount": 0,
    "syncedCount": 0,
    "missing": [],
    "extra": [],
    "goalStale": None,
    "rowsStale": [],
}


def check(map_path, state_path):
    """比对能力图与 state.json 里的指纹。

    **每一项都遵守同一条规则：指纹缺失 → 不报。**
    老项目的 state.json 里没有 goalDigest / rowDigest，不能因此挨断链；
    这条同时让整个改动向后兼容，不需要迁移。
    """
    cur = compute(map_path)
    with open(state_path, encoding="utf-8") as f:
        state = json.load(f)

    mods = state.get("modules") or {}
    if not isinstance(mods, dict):
        mods = {}
    # 「已落」= 有 issue 号。半写入的条目（有 key 没号）不算落成，
    # 它和「压根没建」是同一种状态。
    synced = {
        k: v for k, v in mods.items()
        if isinstance(v, dict) and v.get("issue")
    }

    ids = [r["id"] for r in cur["rows"]]
    missing = [i for i in ids if i not in synced]
    extra = [k for k in synced if k not in ids]

    stored_goal = ((state.get("initiative") or {}) if isinstance(state.get("initiative"), dict) else {}).get("mapDigest")
    if cur["goalDigest"] is None or not stored_goal:
        goal_stale = None          # 判不了 → 不报
    else:
        goal_stale = cur["goalDigest"] != stored_goal

    rows_stale = []
    for r in cur["rows"]:
        entry = synced.get(r["id"])
        if not entry:
            continue
        stored = entry.get("rowDigest")
        if not stored:
            continue               # 没存指纹 → 判不了 → 不报
        if stored != r["digest"]:
            rows_stale.append(r["id"])

    return {
        # ok=False 时两个 hook 一律不报：解析不出模块，或还是模板占位符
        "ok": bool(ids) and not cur["placeholder"],
        "mapCount": len(ids),
        "syncedCount": len(synced),
        "missing": missing,
        "extra": extra,
        "goalStale": goal_stale,
        "rowsStale": rows_stale,
    }


def _selftest():
    import os
    import tempfile

    fails = []

    def chk(name, cond):
        if cond:
            print("  ✅ %s" % name)
        else:
            print("  ❌ %s" % name)
            fails.append(name)

    d = tempfile.mkdtemp()
    m = os.path.join(d, "map.md")
    s = os.path.join(d, "state.json")

    def write_map(rows, goal="给小店主一个能自己上架、自己收款的后台。"):
        body = "# Capability Map: sim\n\n"
        if goal is not None:
            body += "## 目标\n\n%s\n\n" % goal
        body += "## 模块\n\n| Module id | Responsibility | Depends on |\n|---|---|---|\n"
        for r in rows:
            body += "| `%s` | %s | %s |\n" % r
        with open(m, "w", encoding="utf-8") as f:
            f.write(body)

    def write_state(obj):
        with open(s, "w", encoding="utf-8") as f:
            json.dump(obj, f)

    R2 = [("identity", "登录注册", "—"), ("catalog", "商品上架", "identity")]

    # ── 基线：两个模块、都已落、指纹都对得上 ──
    write_map(R2)
    cur = compute(m)
    write_state({
        "initiative": {"issue": 100, "mapDigest": cur["goalDigest"]},
        "modules": {
            r["id"]: {"issue": 100 + i + 1, "rowDigest": r["digest"]}
            for i, r in enumerate(cur["rows"])
        },
    })
    base = check(m, s)
    chk("同步态：missing/rowsStale 空、goalStale=False",
        base["ok"] and not base["missing"] and not base["rowsStale"]
        and base["goalStale"] is False)

    # ── ① 能力图加了一个模块 ──
    write_map(R2 + [("payments", "下单与收款", "catalog")])
    r = check(m, s)
    chk("加了模块 → missing=[payments]", r["missing"] == ["payments"])
    chk("加了模块 → goalStale 仍为 False（目标段没动）", r["goalStale"] is False)

    # ── 数量相等但改了名：数个数看不出来，集合比对能 ──
    write_map([("identity", "登录注册", "—"), ("katalog", "商品上架", "identity")])
    r = check(m, s)
    chk("改名（数量不变）→ missing=[katalog] + extra=[catalog]",
        r["missing"] == ["katalog"] and r["extra"] == ["catalog"]
        and r["mapCount"] == r["syncedCount"])

    # ── ③ 只改职责描述：id 集合没变，rowDigest 变 ──
    write_map([("identity", "登录注册、会话、找回密码", "—"), ("catalog", "商品上架", "identity")])
    r = check(m, s)
    chk("改职责 → rowsStale=[identity]，missing 为空",
        r["rowsStale"] == ["identity"] and not r["missing"])

    # ── ② 只改目标段 ──
    write_map(R2, goal="改成给连锁店用。")
    r = check(m, s)
    chk("改目标段 → goalStale=True，其余干净",
        r["goalStale"] is True and not r["missing"] and not r["rowsStale"])

    # ── 向后兼容：state.json 里没有任何指纹字段 ──
    write_map([("identity", "登录注册、会话、找回密码", "—"), ("catalog", "商品上架", "identity")],
              goal="改成给连锁店用。")
    write_state({"initiative": {"issue": 100}, "modules": {
        "identity": {"issue": 101}, "catalog": {"issue": 102}}})
    r = check(m, s)
    chk("没存指纹 → goalStale=None、rowsStale 空（老项目不挨断链）",
        r["goalStale"] is None and r["rowsStale"] == [])

    # ── 能力图没有 `## 目标` 段（老能力图）──
    write_map(R2, goal=None)
    write_state({"initiative": {"issue": 100, "mapDigest": "deadbeefcafe"},
                 "modules": {"identity": {"issue": 101}, "catalog": {"issue": 102}}})
    r = check(m, s)
    chk("能力图无「## 目标」段 → goalStale=None（不拿存着的指纹硬比）",
        r["goalStale"] is None)

    # ── 模板占位符 ──
    write_map([("example-a", "...", "—"), ("example-b", "...", "example-a")])
    r = check(m, s)
    chk("还是 example-* 占位符 → ok=False", r["ok"] is False)

    # ── 半写入的条目（有 key 没 issue 号）不算已落 ──
    write_map(R2)
    write_state({"initiative": {"issue": 100},
                 "modules": {"identity": {"issue": 101}, "catalog": {}}})
    r = check(m, s)
    chk("有 key 没 issue 号 → 算没落成（missing 含它）",
        r["missing"] == ["catalog"] and r["syncedCount"] == 1)

    # ── 空白归一：行尾空格 / CRLF 不该让指纹变 ──
    write_map(R2)
    a = compute(m)
    with open(m, encoding="utf-8") as f:
        txt = f.read()
    with open(m, "w", encoding="utf-8") as f:
        f.write(txt.replace("\n", "  \r\n"))
    b = compute(m)
    chk("行尾空格 + CRLF 不改变 goalDigest", a["goalDigest"] == b["goalDigest"])

    # ── 但实质内容改一个字必须变 ──
    write_map(R2, goal="给小店主一个能自己上架、自己收款的前台。")
    c = compute(m)
    chk("目标段改一个字 → goalDigest 变", a["goalDigest"] != c["goalDigest"])

    # ── 坏输入：state.json 不是 JSON ──
    with open(s, "w", encoding="utf-8") as f:
        f.write("{{{ not json")
    out = subprocess_json(["check", m, s])
    chk("state.json 坏掉 → 输出「什么都别报」且退 0",
        out.get("ok") is False and out.get("goalStale") is None
        and out.get("missing") == [])

    # ── 坏输入：能力图不存在 ──
    out = subprocess_json(["check", os.path.join(d, "nope.md"), s])
    chk("能力图不存在 → 输出「什么都别报」且退 0", out.get("ok") is False)

    print("")
    if fails:
        print("  spec-digest 自检：%d 条失败" % len(fails))
        return 1
    print("  spec-digest 自检：全部通过")
    return 0


def subprocess_json(argv):
    """用真子进程跑一遍，验的是「异常路径也退 0、也输出合法 JSON」——
    直接调 check() 会抛异常，测不到 main() 里那层兜底。"""
    import subprocess
    p = subprocess.run(
        [sys.executable, os.path.abspath(__file__)] + argv,
        capture_output=True, text=True)
    if p.returncode != 0:
        return {"__rc": p.returncode}
    try:
        return json.loads(p.stdout)
    except Exception:
        return {"__unparsable": p.stdout}


import os  # noqa: E402  （subprocess_json 要用，放这里避免顶部为自检引入依赖）


def main():
    argv = sys.argv[1:]
    if not argv:
        print(__doc__)
        return 2
    if argv[0] == "--selftest":
        return _selftest()
    try:
        if argv[0] == "compute" and len(argv) == 2:
            print(json.dumps(compute(argv[1]), ensure_ascii=False))
            return 0
        if argv[0] == "check" and len(argv) == 3:
            print(json.dumps(check(argv[1], argv[2]), ensure_ascii=False))
            return 0
    except Exception:
        # 探测失败就降级，不误报。**绝不能非零退出或输出非 JSON** ——
        # 调用方是 hook，而 hook 的失败是静默的。
        print(json.dumps(NOTHING, ensure_ascii=False))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
