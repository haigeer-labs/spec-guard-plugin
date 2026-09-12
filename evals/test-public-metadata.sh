#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
repository_url = "https://github.com/haigeer-labs/spec-guard-plugin"
owner_name = "haigeer-labs"

marketplace = json.loads((root / ".claude-plugin/marketplace.json").read_text())
claude = json.loads((root / "plugins/spec-guard/.claude-plugin/plugin.json").read_text())
desktop = json.loads((root / "plugins/spec-guard/manifest.json").read_text())
readme = (root / "README.md").read_text()

assert marketplace["owner"] == {"name": owner_name, "url": repository_url}
assert claude["author"] == {"name": owner_name}
assert claude["homepage"] == repository_url
assert desktop["author"] == {"name": owner_name}
assert f"/plugin marketplace add haigeer-labs/spec-guard-plugin" in readme
assert "yizhongkaimail-collab/spec-guard-plugin" not in readme
print("public metadata points to haigeer-labs/spec-guard-plugin")
PY
