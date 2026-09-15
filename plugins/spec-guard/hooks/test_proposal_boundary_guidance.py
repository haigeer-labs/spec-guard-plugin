"""Pure boundary guidance fixtures; no Git, tracker, or worktree access."""
import json
import unittest

from proposal_boundary_guidance import as_json, guide


class ProposalBoundaryGuidanceTests(unittest.TestCase):
    def test_only_delivery_and_advance_boundaries_get_nonblocking_reminders(self):
        for boundary in ("module-deliver", "module-advance"):
            result = guide(boundary)
            self.assertEqual(result.state, "reminder")
            self.assertEqual(result.boundary, boundary)
            self.assertEqual(result.entries, ("intake", "review", "promotion-proof"))

    def test_ordinary_work_events_do_not_get_proposal_pool_reminders(self):
        result = guide("task-progress")
        self.assertEqual((result.state, result.boundary, result.entries),
                         ("not-applicable", "task-progress", ()))

    def test_empty_or_nonstring_boundary_is_invalid(self):
        for boundary in ("", None, 7):
            result = guide(boundary)
            self.assertEqual((result.state, result.entries), ("invalid", ()))

    def test_json_exposes_only_stable_boundary_and_entry_identifiers(self):
        data = as_json(guide("module-deliver"))
        self.assertEqual(data, {
            "state": "reminder",
            "boundary": "module-deliver",
            "entries": ["intake", "review", "promotion-proof"],
        })
        encoded = json.dumps(data)
        self.assertNotIn("Issue", encoded)
        self.assertNotIn("Capability Map", encoded)


if __name__ == "__main__":
    unittest.main()
