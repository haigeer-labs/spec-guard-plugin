#!/usr/bin/env bash
# 覆盖 GitLab tracker 投影身份的严格、无写入基础契约。
set -euo pipefail

HOOKS="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-}"
case "$MODE" in
  ""|--selftest) ;;
  *) printf 'usage: %s [--selftest]\n' "$0" >&2; exit 2 ;;
esac

PYTHONDONTWRITEBYTECODE=1 python3 - "$HOOKS" "$MODE" <<'PY'
import json
from pathlib import Path
import sys
import unittest

hooks = Path(sys.argv[1])
mode = sys.argv[2]
sys.path.insert(0, str(hooks))

from gitlab_tracker import (  # RED: the shared identity module does not exist yet.
    TrackerIdentityError,
    initiative_marker,
    module_marker,
    parse_issue_page,
    recover_exact_issue,
)


GOAL = "a1b2c3d4e5f6"
ROW = "0123456789ab"


class ProjectionIdentityContract(unittest.TestCase):
    def issue(self, iid, marker, project_id=17, title="untrusted title"):
        return {"iid": iid, "project_id": project_id, "title": title,
                "description": "summary\n\n%s\n" % marker}

    def test_marker_format_is_exact_and_input_is_strict(self):
        self.assertEqual(initiative_marker(GOAL),
                         "<!-- spec-guard-sync:v2 kind=initiative goalDigest=%s -->" % GOAL)
        self.assertEqual(module_marker("audit-tracker-integrity", ROW),
                         "<!-- spec-guard-sync:v2 kind=module id=audit-tracker-integrity rowDigest=%s -->" % ROW)
        for bad in ("", "short", "A1B2C3D4E5F6", "g" * 12):
            with self.subTest(bad=bad):
                with self.assertRaises(TrackerIdentityError):
                    initiative_marker(bad)

    def test_unique_complete_marker_recovers_exact_issue(self):
        marker = initiative_marker(GOAL)
        page = parse_issue_page(json.dumps([self.issue(7, marker)]))
        found = recover_exact_issue(page, marker, project_id=17, page_complete=True)
        self.assertEqual(found["iid"], 7)

    def test_title_or_partial_marker_never_recovers_identity(self):
        marker = initiative_marker(GOAL)
        partial = "<!-- spec-guard-sync:v2 kind=initiative goalDigest=%s" % GOAL
        page = parse_issue_page(json.dumps([
            self.issue(7, partial, title="same title"),
            {"iid": 8, "project_id": 17, "title": marker, "description": "plain text"},
        ]))
        self.assertIsNone(recover_exact_issue(page, marker, project_id=17, page_complete=True))

    def test_multiple_or_incomplete_candidates_fail_closed(self):
        marker = initiative_marker(GOAL)
        page = parse_issue_page(json.dumps([self.issue(7, marker), self.issue(8, marker)]))
        with self.assertRaises(TrackerIdentityError):
            recover_exact_issue(page, marker, project_id=17, page_complete=True)
        with self.assertRaises(TrackerIdentityError):
            recover_exact_issue([self.issue(7, marker)], marker, project_id=17, page_complete=False)

    def test_invalid_json_and_foreign_marker_response_fail_closed(self):
        with self.assertRaises(TrackerIdentityError):
            parse_issue_page("{not json")
        marker = initiative_marker(GOAL)
        page = parse_issue_page(json.dumps([self.issue(7, marker, project_id=99)]))
        with self.assertRaises(TrackerIdentityError):
            recover_exact_issue(page, marker, project_id=17, page_complete=True)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ProjectionIdentityContract)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if mode == "--selftest" and result.wasSuccessful():
        print("selftest: title-only and partial-marker recovery are rejected")
    raise SystemExit(not result.wasSuccessful())
PY
