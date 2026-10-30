"""Global tab traversal includes shells and every machine, without touching programs."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("navigate", Path(__file__).resolve().parents[1] / "scripts/herdr-navigate.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Navigation(unittest.TestCase):
    def setUp(self):
        self.snapshot = {"spaces": [
            {"active": True, "tabs": [{"id": "a", "active": True}, {"id": "b"}, {"id": "hidden", "settled": True}]},
            {"tabs": [{"id": "mini/c"}, {"id": "mini/d"}]},
        ]}

    def test_visits_shell_tabs_and_crosses_spaces_and_machines(self):
        self.assertEqual(module.destination(self.snapshot, 1), "b")
        self.snapshot["spaces"][0]["tabs"][0]["active"] = False
        self.snapshot["spaces"][0]["tabs"][1]["active"] = True
        self.assertEqual(module.destination(self.snapshot, 1), "mini/c")

    def test_wraps_in_both_directions(self):
        self.assertEqual(module.destination(self.snapshot, -1), "mini/d")
        self.snapshot["spaces"][0]["active"] = False
        self.snapshot["spaces"][1]["active"] = True
        self.snapshot["spaces"][1]["tabs"][1]["active"] = True
        self.assertEqual(module.destination(self.snapshot, 1), "a")

    def test_remembered_active_tabs_in_other_spaces_are_not_current(self):
        self.snapshot["spaces"][1]["tabs"][0]["active"] = True
        self.assertEqual(module.destination(self.snapshot, 1), "b")

    def test_empty_or_no_selection(self):
        self.assertIsNone(module.destination({"spaces": []}, 1))
        self.snapshot["spaces"][0]["active"] = False
        self.assertEqual(module.destination(self.snapshot, 1), "a")
        self.assertEqual(module.destination(self.snapshot, -1), "mini/d")

    def test_invalid_or_duplicate_ids_fail_instead_of_guessing(self):
        self.snapshot["spaces"][1]["tabs"][0]["id"] = "a"
        with self.assertRaises(ValueError):
            module.destination(self.snapshot, 1)
        with self.assertRaises((ValueError, KeyError, TypeError)):
            module.destination({"spaces": [{"tabs": [{"id": ""}]}]}, 1)

if __name__ == "__main__":
    unittest.main()
