"""Native close/restore refuses unknown identities and preserves exact conversations."""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "native", Path(__file__).resolve().parents[1] / "scripts/herdr-native.py"
)
n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(n)

SID = "00000000-0000-4000-8000-000000000001"


class NativeTests(unittest.TestCase):
    def test_exact_resume_commands(self):
        for agent, expected in [
            ("codex", ["codex", "resume", SID]),
            ("claude", ["claude", "--resume", SID]),
        ]:
            record = {
                "status": {"app": agent},
                "labels": {"session.agent": agent, "session.id": SID},
                "cwd": "/workspace",
            }
            self.assertEqual(n.resume_record(record)["argv"], expected)
        self.assertEqual(
            n.resume_record(
                {
                    "status": {"app": "pi"},
                    "labels": {
                        "session.agent": "pi",
                        "session.id": "opaque",
                        "session.file": "/sessions/session.jsonl",
                    },
                    "cwd": "/workspace",
                }
            )["argv"],
            ["pi", "--session", "/sessions/session.jsonl"],
        )

    def test_unknown_or_invalid_agent_identity_prevents_close(self):
        for record in [
            {"status": {"app": "codex"}, "labels": {}, "cwd": "/workspace"},
            {
                "status": {"app": "codex"},
                "labels": {"session.agent": "codex", "session.id": "latest"},
                "cwd": "/workspace",
            },
            {
                "status": {"app": "pi"},
                "labels": {"session.agent": "pi", "session.file": "relative.jsonl"},
                "cwd": "/workspace",
            },
            {"status": None, "foreground": {"name": "vim"}, "cwd": "/workspace"},
        ]:
            with self.assertRaises(ValueError):
                n.resume_record(record)

    def test_shells_are_reopened_without_replaying_commands(self):
        self.assertEqual(
            n.resume_record(
                {"status": None, "foreground": {"name": "zsh"}, "cwd": "/workspace"}
            )["argv"],
            [],
        )

    def test_short_titles_and_manual_names(self):
        self.assertEqual(
            n.short_title("please fix the checkout bug in payments"), "Fix Checkout Bug"
        )
        self.assertLessEqual(
            len(n.short_title("investigate extraordinarilylongproblem with queues")), 24
        )
        self.assertEqual(n.short_title(""), "")
        self.assertFalse(n.replace_title("My Label", "Last Automatic", "New Automatic"))
        self.assertTrue(
            n.replace_title("Last Automatic", "Last Automatic", "New Automatic")
        )
        self.assertTrue(n.replace_title("1", None, "New Automatic", named=False))

    def test_nested_split_plan(self):
        tree = {
            "type": "row",
            "children": [
                {
                    "type": "column",
                    "children": [
                        {"id": "a", "content": {"terminal": "t1"}},
                        {"id": "b", "content": {"terminal": "t2"}},
                    ],
                },
                {"id": "c", "content": {"terminal": "t3"}},
            ],
        }
        calls = []

        def app(command, **args):
            calls.append((command, args))
            return {"pane": "new" + str(len(calls))}

        with patch.object(n, "app", app):
            n.restore_splits(
                tree,
                "first",
                {
                    "t1": {"argv": [], "cwd": "/a"},
                    "t2": {"argv": [], "cwd": "/b"},
                    "t3": {"argv": [], "cwd": "/c"},
                },
            )
        opens = [args for command, args in calls if command == "terminal.open"]
        self.assertEqual(
            [(o["place"], o["folder"]) for o in opens],
            [("right", "/c"), ("down", "/b")],
        )

    def test_atomic_archive_is_private_and_keeps_previous_on_invalid_write(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "archive.json"
            n.save(path, [{"id": "closed"}])
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(n.load(path), [{"id": "closed"}])
            with self.assertRaises(TypeError):
                n.save(path, [{"bad": object()}])
            self.assertEqual(n.load(path), [{"id": "closed"}])

    def test_reopen_refuses_to_duplicate_a_live_original(self):
        entry = {"original_tab": "original", "snapshot": {}}
        with (
            patch.object(
                n, "app", return_value={"spaces": [{"tabs": [{"id": "original"}]}]}
            ),
            self.assertRaises(ValueError),
        ):
            n.ensure_closed(entry)

    def test_reopen_refuses_the_same_conversation_in_another_tab(self):
        entry = {
            "original_tab": "gone",
            "records": {"t1": {"argv": ["codex", "resume", SID]}},
        }
        with (
            patch.object(n, "app", return_value={"spaces": []}),
            patch.object(
                n,
                "run",
                return_value={
                    "terminals": [{"state": "live", "labels": {"session.id": SID}}]
                },
            ),
            self.assertRaises(ValueError),
        ):
            n.ensure_closed(entry)

    def test_close_saves_snapshot_before_ending_process(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "archive.json"
            entry = {"id": "closed", "original_tab": "selected"}

            def close(command, **args):
                self.assertEqual(n.load(path), [entry])
                self.assertEqual(
                    (command, args),
                    ("tab.close", {"id": "selected", "confirmed": True}),
                )

            with (
                patch.object(n, "capture", return_value=entry),
                patch.object(n, "check_snapshot"),
                patch.object(n, "app", side_effect=close),
            ):
                n.close_tab(path)

    def test_unsafe_capture_never_ends_a_process(self):
        with (
            patch.object(n, "capture", side_effect=ValueError("Missing identity")),
            patch.object(n, "app") as call,
        ):
            with self.assertRaises(ValueError):
                n.close_tab(Path("/unused"))
            call.assert_not_called()

    def test_closed_remote_agent_reopens_exact_identity_after_last_space_closes(self):
        world = {
            "spaces": [
                {
                    "id": "mini/sp1",
                    "machine": "mini",
                    "active": True,
                    "tabs": [
                        {
                            "id": "mini/tab1",
                            "name": "Checkout Fix",
                            "active": True,
                            "terminals": [{"terminal": "mini/t1", "pane": "mini/p1"}],
                        }
                    ],
                }
            ]
        }
        tree = {
            "id": "tab1",
            "type": "row",
            "children": [{"id": "p1", "content": {"terminal": "t1"}}],
        }
        document = {
            "value": {
                "spaces": [
                    {
                        "id": "sp1",
                        "name": "Work",
                        "folder": "/workspace",
                        "tabs": [{"id": "tab1", "name": "Checkout Fix", "root": tree}],
                    }
                ]
            }
        }
        calls = []

        def app(command, **args):
            calls.append((command, args))
            if command == "ls":
                return world
            if command == "status":
                return {"focused_pane": "mini/p1"}
            if command == "tab.close":
                world["spaces"] = []
                return {}
            if command == "space.new":
                world["spaces"] = [
                    {
                        "id": "mini/new-space",
                        "tabs": [
                            {
                                "id": "mini/new-tab",
                                "terminals": [{"pane": "mini/new-pane"}],
                            }
                        ],
                    }
                ]
                return {
                    "space": "mini/new-space",
                    "tab": "mini/new-tab",
                    "terminal": "mini/new-terminal",
                }
            return {}

        def run(args, **kwargs):
            if args[1] == "get":
                return {
                    "status": {"app": "codex", "state": "idle"},
                    "labels": {"session.agent": "codex", "session.id": SID},
                    "cwd": "/workspace",
                }
            if args[1] == "ls":
                return {"terminals": []}
            if args[1:3] == ["machine", "ls"]:
                return {"machines": [{"id": "machine-id", "name": "mini"}]}
            if args[1] == "label":
                return {}
            raise AssertionError(args)

        with (
            tempfile.TemporaryDirectory() as d,
            patch.object(n, "app", side_effect=app),
            patch.object(n, "run", side_effect=run),
            patch.object(n, "rpc", return_value=document),
        ):
            path = Path(d) / "archive.json"
            n.close_tab(path)
            self.assertEqual(len(n.load(path)), 1)
            n.reopen(path)
            self.assertEqual(n.load(path), [])
        new = next(args for command, args in calls if command == "space.new")
        self.assertEqual(new["argv"], ["codex", "resume", SID])
        self.assertEqual(new["machine"], "mini")
        self.assertEqual(new["tab"], "Checkout Fix")
        self.assertEqual(new["folder"], "/workspace")

    def test_failed_restore_keeps_a_receipt_and_history(self):
        entry = {
            "id": "receipt",
            "original_tab": "gone",
            "space": "sp1",
            "name": "Saved",
            "records": {"t1": {"argv": [], "cwd": "/work"}},
            "tree": {"id": "p1", "content": {"terminal": "t1"}},
            "index": 1,
        }
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "archive.json"
            n.save(path, [entry])
            with (
                patch.object(
                    n,
                    "app",
                    side_effect=lambda command, **args: (
                        {"spaces": [{"id": "sp1", "tabs": []}]}
                        if command == "ls"
                        else (_ for _ in ()).throw(ValueError("disconnected"))
                    ),
                ),
                self.assertRaises(ValueError),
            ):
                n.reopen(path)
            self.assertTrue(n.load(path)[0]["restoring"])
            self.assertEqual(n.load(path)[0]["id"], "receipt")

    def test_exact_native_locator_never_uses_inherited_pane_identity(self):
        records = {
            "terminals": [
                {
                    "address": "t7",
                    "labels": {
                        "session.agent": "codex",
                        "session.id": SID,
                        "herdr.tab": "saved-tab",
                        "herdr.space": "space",
                    },
                }
            ]
        }
        with patch.object(n, "run", return_value=records):
            self.assertEqual(n.locate("codex", SID)["terminal_id"], "t7")
            with self.assertRaises(LookupError):
                n.locate("codex", "00000000-0000-4000-8000-000000000002")
            records["terminals"].append(records["terminals"][0])
            with self.assertRaises(ValueError):
                n.locate("codex", SID)

    def test_pane_navigation_cycles_through_mod_panes_and_wraps(self):
        world = {
            "spaces": [
                {
                    "active": True,
                    "machine": "mini",
                    "tabs": [{"active": True, "id": "mini/tab"}],
                }
            ]
        }
        document = {
            "value": {
                "spaces": [
                    {
                        "tabs": [
                            {
                                "id": "tab",
                                "root": {
                                    "type": "row",
                                    "children": [
                                        {"id": "one", "content": {"terminal": "t1"}},
                                        {"id": "two", "content": {"mod": "notes"}},
                                        {"id": "three", "content": {"terminal": "t3"}},
                                    ],
                                },
                            }
                        ]
                    }
                ]
            }
        }
        calls = []

        def app(command, **args):
            if command == "ls":
                return world
            if command == "status":
                return {"focused_pane": "mini/one"}
            calls.append((command, args))
            return {}

        with (
            patch.object(n, "app", side_effect=app),
            patch.object(n, "rpc", return_value=document),
        ):
            n.cycle_pane(-1)
        self.assertEqual(calls, [("pane.focus", {"pane": "mini/three"})])

    def test_agent_written_title_wins_and_native_task_title_beats_prompt_fallback(self):
        record = {
            "title": "Repair Checkout | workstation",
            "labels": {
                "session.agent": "codex",
                "session.title": "Please Fix Checkout",
            },
        }
        self.assertEqual(n.preferred_title(record), "Repair Checkout")
        record["labels"]["session.explicit-title"] = "1"
        self.assertEqual(n.preferred_title(record), "Please Fix Checkout")
        record["labels"].pop("session.explicit-title")
        record["title"] = "Codex"
        self.assertEqual(n.preferred_title(record), "Please Fix Checkout")

    def test_legacy_adapters_do_not_report_a_core_terminal_as_a_tui_pane(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            claude = root / ".claude/hooks/herdr-agent-state.sh"
            pi = root / ".pi/agent/extensions/herdr-agent-state.ts"
            claude.parent.mkdir(parents=True)
            pi.parent.mkdir(parents=True)
            claude.write_text("#!/bin/sh\nset -eu\nprintf legacy\n")
            pi.write_text(
                'function enabled() { return HERDR_ENV === "1" && !!socketPath; }'
            )
            n.guard_legacy(root)
            n.guard_legacy(root)
            self.assertEqual(claude.read_text().count("HC_TERMINAL_ID"), 1)
            self.assertIn("!process.env.HC_TERMINAL_ID", pi.read_text())

    def test_eager_resume_registration_uses_created_terminal_not_inherited_context(
        self,
    ):
        with patch.object(n, "run", return_value={}) as call:
            n.label_restored(
                {"terminal": "mini/new"},
                {
                    "argv": ["codex", "resume", SID],
                    "cwd": "/workspace",
                    "title": "Saved Task",
                },
            )
            args = call.call_args.args[0]
            self.assertEqual(args[1:3], ["label", "mini/new"])
            self.assertIn("session.id=" + SID, args)

    def test_changed_split_tree_is_not_closed_from_an_old_snapshot(self):
        entry = {
            "original_tab": "tab",
            "machine": None,
            "tree": {"id": "old"},
            "records": {},
        }
        document = {
            "value": {"spaces": [{"tabs": [{"id": "tab", "root": {"id": "new"}}]}]}
        }
        with (
            patch.object(n, "rpc", return_value=document),
            self.assertRaises(ValueError),
        ):
            n.check_snapshot(entry)


if __name__ == "__main__":
    unittest.main()
