#!/usr/bin/env python3
"""只读严格解析能力图：capability-map.py <map-path>，单个 JSON，失败非零。"""
import argparse
import json
import sys

from capability_map import MapError, parse_map


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("map_path")
    args = parser.parse_args(argv)
    try:
        parsed = parse_map(args.map_path)
        result = {
            "ok": True,
            "modules": [{"id": row.module_id, "responsibility": row.responsibility,
                         "dependsOn": row.depends_on} for row in parsed.rows],
            "orderGroups": parsed.order_groups,
            "order": parsed.order,
        }
    except (MapError, OSError, UnicodeError) as error:
        result = {"ok": False, "error": str(error)}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
