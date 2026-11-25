"""Native close/restore refuses unknown identities and preserves exact conversations."""

import subprocess
import os
import sys
import json
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


class SelfCloseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.record = {"address": "t1", "cwd": "/workspace", "state": "live",
                       "labels": {"session.agent": "codex", "session.id": SID,
                                  "herdr.tab": "own", "dispatch.task": "task-id"}}
        self.tab = {"id": "own", "name": "Fix Close", "root": {
            "id": "root", "type": "row", "children": [
                {"id": "pane", "content": {"terminal": "t1"}}]}}
        self.document = {"version": 7, "value": {"spaces": [
            {"id": "space", "name": "Work", "folder": "/workspace",
             "tabs": [self.tab, {"id": "other", "root": {}}]}]}}
        self.killed = []
        self.written = None
        self.conflict = False
        self.addCleanup(patch.stopall)
        patch.object(n, "STATE", self.directory).start()
        patch.dict(os.environ, CODEX_THREAD_ID=SID).start()
        patch.object(n, "live_records", return_value=[self.record]).start()
        patch.object(n, "rpc", side_effect=self.rpc).start()
        patch.object(n, "run", side_effect=self.run_core).start()
        patch.object(n, "app", side_effect=AssertionError("No desktop CLI on this host")).start()

    def rpc(self, method, **params):
        if method == "doc.get":
            self.assertEqual(params, {"name": "herdr-app"})
            return json.loads(json.dumps(self.document))
        self.assertEqual(method, "doc.set")
        self.assertEqual(params["version"], 7)
        self.assertEqual(params["name"], "herdr-app")
        self.assertTrue((self.directory / "archive.json").exists())
        if self.conflict:
            raise ValueError("conflict")
        self.written = params["value"]
        return {"version": 8}

    def run_core(self, argv, **kwargs):
        if argv == [n.HC, "get", "t1"]:
            return self.record
        if argv == [n.HC, "label", "t1", "dispatch.task="]:
            return {}
        self.assertEqual(argv, [n.HC, "kill", "t1"])
        self.assertEqual([t["id"] for t in self.written["spaces"][0]["tabs"]], ["other"])
        self.killed.append("t1")
        return {}

    def test_core_self_close_archives_exact_resume_and_removes_only_own_tab(self):
        n.close_session("codex", SID)
        self.assertEqual(self.killed, ["t1"])
        saved = n.load(self.directory / "archive.json")[-1]
        self.assertEqual(saved["records"]["t1"]["argv"], ["codex", "resume", SID])
        self.assertEqual(saved["original_tab"], "own")
        self.assertEqual(saved["tree"], self.tab["root"])

    def test_dry_run_has_no_mutations(self):
        n.close_session("codex", SID, dry_run=True)
        self.assertEqual(self.killed, [])
        self.assertIsNone(self.written)
        self.assertFalse((self.directory / "archive.json").exists())

    def test_shared_or_stale_tab_never_closes_any_terminal(self):
        for content in ({"terminal": "t2"}, {"mod": "editor"}):
            self.tab["root"]["children"].append({"id": "second", "content": content})
            with self.assertRaisesRegex(ValueError, "Shared tab"):
                n.close_session("codex", SID)
            self.tab["root"]["children"].pop()
        self.tab["root"]["children"][0]["content"]["terminal"] = "t2"
        with self.assertRaises(ValueError):
            n.close_session("codex", SID)
        self.assertEqual(self.killed, [])
        self.assertIsNone(self.written)

    def test_native_identity_and_document_conflicts_fail_closed(self):
        with patch.dict(os.environ, CODEX_THREAD_ID="different"):
            with self.assertRaisesRegex(ValueError, "identity"):
                n.close_session("codex", SID)
        self.conflict = True
        with self.assertRaisesRegex(ValueError, "conflict"):
            n.close_session("codex", SID)
        self.assertEqual(self.killed, [])
        self.assertIsNone(self.written)

    def test_changed_or_duplicate_conversation_never_closes(self):
        changed = {**self.record, "labels": {"session.agent": "codex",
                   "session.id": "00000000-0000-4000-8000-000000000002"}}
        with patch.object(n, "run", return_value=changed):
            with self.assertRaisesRegex(ValueError, "identity changed"):
                n.close_session("codex", SID)
        with patch.object(n, "live_records", return_value=[self.record, self.record]):
            with self.assertRaisesRegex(ValueError, "Multiple"):
                n.close_session("codex", SID)
        self.assertEqual(self.killed, [])
        self.assertIsNone(self.written)


class NativeTests(unittest.TestCase):
    def test_connected_guard_is_read_only_and_revalidates_selection(self):
        world={"spaces":[{"id":"remote","active":True,"machine":"box","tabs":[{"id":"t","active":True}]}]}
        with patch.object(n,"run",side_effect=[world,{"machines":[{"name":"box","state":"connected"}]},world]) as run, patch.object(n,"rpc",return_value={}) as rpc:
            n.check_connection("new")
            self.assertEqual([call.args[0] for call in run.call_args_list],[[n.APP,"ls"],[n.HC,"machine","ls"],[n.APP,"ls"]])
            rpc.assert_called_once_with("doc.get",name="herdr-hotkey-check",on="box",timeout=0.8)

    def test_stale_link_probe_has_real_bounded_process_timeout(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            fake=root/"app"; core=root/"core"
            world={"spaces":[{"id":"s","active":True,"machine":"box","tabs":[]}]}
            fake.write_text("#!"+sys.executable+"\nimport json\nprint("+repr(json.dumps(world))+")\n")
            core.write_text("#!"+sys.executable+"\nimport sys,time\nif sys.argv[1]=='connect': time.sleep(4)\nelse: print('"+json.dumps({"machines":[{"name":"box","state":"connected"}]})+"')\n")
            fake.chmod(0o700);core.chmod(0o700)
            result=subprocess.run([sys.executable,n.__file__,"check-connection","--action","new"],env={**os.environ,"HERDR_NATIVE_STATE_DIR":d,"HERDR_APP_BIN":str(fake),"HERDR_CORE_BIN":str(core)},capture_output=True,text=True,timeout=2)
            self.assertEqual(result.returncode,1)
            self.assertIn("box is not responding",result.stderr)

    def test_connection_guard_refuses_known_offline_without_remote_probe(self):
        world={"spaces":[{"id":"remote","active":True,"machine":"box","tabs":[{"id":"t","active":True}]}]}
        with patch.object(n,"run",side_effect=[world,{"machines":[{"name":"box","state":"disconnected"}]}]), patch.object(n,"rpc") as rpc:
            with self.assertRaisesRegex(ValueError,"box.*disconnected"):
                n.check_connection("close")
            rpc.assert_not_called()

    def test_connection_guard_probes_stale_connected_state_with_deadline(self):
        world={"spaces":[{"id":"remote","active":True,"machine":"box","tabs":[{"id":"t","active":True}]}]}
        with patch.object(n,"run",side_effect=[world,{"machines":[{"name":"box","state":"connected"}]}]), patch.object(n,"rpc",side_effect=subprocess.TimeoutExpired("probe",0.8)) as rpc:
            with self.assertRaisesRegex(ValueError,"box.*not responding"):
                n.check_connection("new")
            self.assertEqual(rpc.call_args.kwargs["timeout"],0.8)

    def test_connection_guard_leaves_local_actions_independent(self):
        with patch.object(n,"run",return_value={"spaces":[{"id":"local","active":True,"machine":None} ]}) as run, patch.object(n,"rpc") as rpc:
            n.check_connection("new")
            self.assertEqual(run.call_count,1)
            rpc.assert_not_called()

    def test_connection_guard_uses_restore_machine_identity(self):
        saved={"id":"undo","machine":"old-name","machine_id":"saved"}
        with patch.object(n,"load",return_value=[saved]), patch.object(n,"run",return_value={"machines":[{"id":"saved","name":"renamed","state":"needs_login"}]}), patch.object(n,"rpc") as rpc:
            with self.assertRaisesRegex(ValueError,"renamed.*needs login"):
                n.check_connection("reopen")
            rpc.assert_not_called()

    def test_connection_guard_does_not_act_after_focus_changes(self):
        world={"spaces":[{"id":"remote","active":True,"machine":"box","tabs":[{"id":"t","active":True}]}]}
        changed={"spaces":[{"id":"local","active":True,"machine":None}]}
        with patch.object(n,"run",side_effect=[world,{"machines":[{"name":"box","state":"connected"}]},changed]), patch.object(n,"rpc",return_value={}):
            with self.assertRaisesRegex(ValueError,"selection changed"):
                n.check_connection("close")

    def test_close_dispatch_does_not_wait_for_archive_lock(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            fake=root/"app"
            fake.write_text("#!"+sys.executable+"\nimport json,sys\nprint(json.dumps({'layout':'terminals-agents'} if sys.argv[1]=='status' else {'ok':True}))\n")
            fake.chmod(0o700)
            with (root/"lock").open("a") as lock:
                n.fcntl.flock(lock,n.fcntl.LOCK_EX)
                result=subprocess.run([sys.executable,n.__file__,"close"],env={**os.environ,"HERDR_NATIVE_STATE_DIR":d,"HERDR_APP_BIN":str(fake)},capture_output=True,timeout=3)
            self.assertEqual(result.returncode,0,result.stderr)

    def test_title_refresh_uses_an_independent_nonblocking_lock(self):
        with tempfile.TemporaryDirectory() as d, patch.object(n,"STATE",Path(d)), patch.object(n,"titles") as titles, patch.object(n,"core_titles"):
            with patch.object(n.fcntl,"flock") as flock:
                n.refresh_titles()
                self.assertEqual(flock.call_args.args[1], n.fcntl.LOCK_EX | n.fcntl.LOCK_NB)
            titles.assert_called_once_with(Path(d)/"titles.json")
            with patch.object(n.fcntl,"flock") as flock:
                n.refresh_titles(wait=True)
                self.assertEqual(flock.call_args.args[1],n.fcntl.LOCK_EX)
            titles.reset_mock()
            with patch.object(n.fcntl,"flock",side_effect=BlockingIOError):
                n.refresh_titles()
            titles.assert_not_called()
            self.assertTrue((Path(d)/"titles.lock").exists())
            self.assertFalse((Path(d)/"lock").exists())

    def test_group_close_reuses_preflight_snapshots(self):
        entries=[{"id":"one","original_tab":"a"},{"id":"two","original_tab":"b"}]
        def app(command,**kwargs):
            return {"spaces":[{"tabs":[{"id":"a"},{"id":"b"}]}]} if command=="ls" else {}
        with patch.object(n,"app",side_effect=app), patch.object(n,"capture",side_effect=entries) as capture, patch.object(n,"load",return_value=[]), patch.object(n,"save"), patch.object(n,"check_snapshot") as check:
            n.close_group(Path("archive"),["a","b"])
            self.assertEqual(capture.call_count,2)
            self.assertEqual(check.call_count,2)

    def test_group_close_preflights_every_tab_before_closing_any(self):
        with patch.object(n,"app",return_value={"spaces":[{"tabs":[{"id":"a"},{"id":"b"}]}]}), patch.object(n,"capture",side_effect=[{},ValueError("Unknown job")]), patch.object(n,"close_tab") as close:
            with self.assertRaises(ValueError):n.close_group(Path("archive"),["a","b"])
            close.assert_not_called()
        with patch.object(n,"app",return_value={"spaces":[{"tabs":[{"id":"a"},{"id":"b"}]}]}), patch.object(n,"capture",return_value={}), patch.object(n,"close_tab") as close:
            n.close_group(Path("archive"),["a","b"])
            self.assertEqual([c.args[1] for c in close.call_args_list],["a","b"])

    def test_group_close_rejects_stale_duplicate_or_cross_space_ids(self):
        with patch.object(n,"app",return_value={"spaces":[{"tabs":[{"id":"a"}]},{"tabs":[{"id":"b"}]}]}), patch.object(n,"close_tab") as close:
            for ids in ([],["a","a"],["gone"],["a","b"]):
                with self.assertRaises(ValueError):n.close_group(Path("archive"),ids)
            close.assert_not_called()

    def test_agent_titles_are_two_words_but_shell_commands_stay_intact(self):
        self.assertEqual(n.short_title("Fix Broken Checkout Flow"),"Fix Broken")
        self.assertEqual(n.preferred_title({"labels":{"session.agent":"codex"},"title":"loginname"}),"New Session")
        self.assertEqual(n.preferred_title({"labels":{"session.agent":"codex","session.explicit-title":"1","session.title":"Checkout"}}),"Checkout Session")
        self.assertEqual(n.preferred_title({"labels":{"session.agent":"codex","session.explicit-title":"1","session.title":"Fix Broken Checkout"}}),"Fix Broken")

    def test_shell_hook_keeps_command_at_prompt_and_strips_control_characters(self):
        hook = Path(__file__).resolve().parents[1] / "home/zsh/herdr-title.zsh"
        result = subprocess.run(["zsh", "-f", "-c", 'source "$1"; _herdr_command_preexec $\'git status\\n--short\'; _herdr_command_title', "test", str(hook)], env={"HC_TERMINAL_ID":"fixture"}, capture_output=True, check=True)
        self.assertEqual(result.stdout, b"\x1b]2;git status --short\x07" * 2)

    def test_shell_titles_preserve_the_last_command_and_agent_names(self):
        self.assertEqual(n.preferred_title({"argv":["/bin/zsh"],"title":"git status --short"}), "git status --short")
        self.assertEqual(n.preferred_title({"argv":["/bin/zsh"],"title":"  "}), "")
        self.assertEqual(n.preferred_title({"argv":["codex"],"title":"git status"}), "")

    def test_live_summaries_are_expanded_before_identity_or_naming(self):
        full = {
            "address": "mini/t1",
            "labels": {"session.agent": "codex", "session.id": SID},
        }
        with patch.object(
            n,
            "run",
            side_effect=[
                {"terminals": [{"address": "mini/t1", "agent": "codex"}]},
                full,
            ],
        ) as call:
            self.assertEqual(n.live_records(), [full])
            self.assertEqual(call.call_args.args[0], [n.HC, "get", "mini/t1"])

    def test_terminal_removed_during_listing_does_not_stop_title_updates(self):
        missing = subprocess.CalledProcessError(
            3, [], output='{"error":{"kind":"not_found"}}'
        )
        with patch.object(
            n, "run", side_effect=[{"terminals": [{"address": "t1"}]}, missing]
        ):
            self.assertEqual(n.live_records(), [])
        missing_stderr = subprocess.CalledProcessError(
            3, [], output="", stderr='{"error":{"kind":"not_found"}}'
        )
        with patch.object(n, "run", side_effect=[{"terminals": [{"address": "t1"}]}, missing_stderr]):
            self.assertEqual(n.live_records(), [])
        unreachable = subprocess.CalledProcessError(
            1, [], output='{"error":{"kind":"unreachable"}}'
        )
        with (
            patch.object(
                n,
                "run",
                side_effect=[{"terminals": [{"address": "mini/t1"}]}, unreachable],
            ),
            self.assertRaises(subprocess.CalledProcessError),
        ):
            n.live_records()

    def test_wrapped_core_events_refresh_titles(self):
        self.assertTrue(n.title_event({"method": "event", "params": {"type": "created"}}))
        self.assertTrue(
            n.title_event(
                {
                    "jsonrpc": "2.0",
                    "method": "event",
                    "params": {"type": "labels", "terminal": "mini/t1"},
                }
            )
        )
        self.assertTrue(n.title_event({"terminals": []}))
        self.assertFalse(
            n.title_event({"method": "event", "params": {"type": "output"}})
        )

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

    def test_unregistered_agent_close_uses_explicit_picker_not_a_guessed_session(self):
        for agent, picker in [
            ("codex", ["codex", "resume"]),
            ("claude", ["claude", "--resume"]),
        ]:
            saved = n.resume_record(
                {
                    "status": {"app": agent, "state": "idle"},
                    "labels": {},
                    "cwd": "/workspace",
                }
            )
            self.assertEqual(saved["argv"], picker)
            n.validate_spec(saved)
            with patch.object(n, "run") as call:
                n.label_restored({"terminal": "mini/new"}, saved)
                call.assert_not_called()

    def test_shells_are_reopened_without_replaying_commands(self):
        self.assertEqual(
            n.resume_record(
                {"status": None, "foreground": {"name": "zsh"}, "cwd": "/workspace"}
            )["argv"],
            [],
        )

    def test_short_titles_and_manual_names(self):
        self.assertEqual(
            n.short_title("please fix the checkout bug in payments"), "Fix Checkout"
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
            entry = n.load(path)[0]
            previous = json.loads(json.dumps(entry))
            previous["original_tab"] = "mini/previous-tab"
            n.save(path, [previous, entry])
            n.reopen(path)
            remaining = n.load(path)
            self.assertEqual(len(remaining), 1)
            self.assertEqual(remaining[0]["space"], "mini/new-space")
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

    def test_headless_dispatch_gets_one_named_tab_in_its_destination(self):
        document = {"version": 3, "value": {"spaces": [{"id": "captures", "tabs": []}]}}
        record = {"address": "t1", "labels": {"dispatch.task": "opaque", "herdr.space": "captures", "session.title": "Repair Checkout"}}
        with tempfile.TemporaryDirectory() as d, patch.object(n, "rpc", return_value=document), patch.object(n, "live_records", return_value=[record]), patch.object(n, "run", return_value={}) as run:
            path = Path(d) / "titles.json"
            n.core_titles(path)
            tabs = document["value"]["spaces"][0]["tabs"]
            self.assertEqual(len(tabs), 1)
            self.assertEqual(tabs[0]["name"], "Repair Checkout")
            self.assertEqual(tabs[0]["root"]["children"][0]["content"]["terminal"], "t1")
            run.assert_called_with([n.HC, "label", "t1", "herdr.tab=" + tabs[0]["id"]])
            n.core_titles(path)
            self.assertEqual(len(tabs), 1)

    def test_core_refresh_reuses_desktop_automatic_title_ownership(self):
        with tempfile.TemporaryDirectory() as d, patch.object(n, "STATE", Path(d)), patch.object(n, "core_titles") as core, patch.object(n, "titles"):
            n.refresh_titles()
            core.assert_called_once_with(Path(d) / "titles.json")

    def test_declared_spaces_preserve_tabs_and_are_idempotent(self):
        document = {"version": 4, "value": {"spaces": [
            {"id": "default", "name": "", "tabs": [{"id": "existing"}]},
            {"id": "other", "name": "Personal", "tabs": []},
        ]}}
        with patch.object(n, "rpc", return_value=document) as rpc:
            n.configure_spaces({"default": "Default", "captures": "Captures"})
            spaces = document["value"]["spaces"]
            self.assertEqual([s["name"] for s in spaces], ["Default", "Personal", "Captures"])
            self.assertEqual(spaces[0]["tabs"], [{"id": "existing"}])
            self.assertEqual(spaces[2]["tabs"], [])
            self.assertEqual(rpc.call_args.kwargs["version"], 4)
            rpc.reset_mock()
            n.configure_spaces({"default": "Default", "captures": "Captures"})
            self.assertEqual(rpc.call_count, 1)

    def test_headless_naming_does_not_require_an_app_executable(self):
        with patch.object(n, "app", side_effect=FileNotFoundError("no viewer")):
            n.titles(Path("unused"))

    def test_registration_keeps_launch_title_but_clears_previous_conversation(self):
        for previous, expected in [
            ({"session.title": "Repair Checkout", "dispatch.task": "opaque-task"}, "Repair Checkout"),
            ({"session.id": "old", "session.title": "Old Work"}, ""),
        ]:
            with patch.object(n, "run", return_value={"labels": previous}) as run:
                n.register("codex", SID, terminal="t1")
                labels = dict(arg.split("=", 1) for arg in run.call_args.args[0][3:])
                self.assertEqual(labels["session.title"], expected)

    def test_headless_titles_follow_agent_labels_and_preserve_manual_names(self):
        document = {"version": 7, "value": {"spaces": [{"tabs": [
            {"id": "automatic", "name": "", "root": {"content": {"terminal": "t1"}}},
            {"id": "manual", "name": "My Custom Name", "root": {"content": {"terminal": "t2"}}},
        ]}]}}
        records = [{"address": terminal, "labels": {"session.agent": "codex",
                   "session.explicit-title": "1", "session.title": "Repair Checkout"}}
                   for terminal in ("t1", "t2")]
        with tempfile.TemporaryDirectory() as d, patch.object(n, "rpc", return_value=document) as rpc, patch.object(n, "live_records", return_value=records):
            path = Path(d) / "titles.json"
            n.core_titles(path)
            self.assertEqual(document["value"]["spaces"][0]["tabs"][0]["name"], "Repair Checkout")
            self.assertEqual(document["value"]["spaces"][0]["tabs"][1]["name"], "My Custom Name")
            self.assertEqual(rpc.call_args.kwargs["version"], 7)
            rpc.reset_mock()
            n.core_titles(path)
            self.assertEqual(rpc.call_count, 1)
            records[0]["labels"]["session.title"] = "Review Payment"
            n.core_titles(path)
            self.assertEqual(document["value"]["spaces"][0]["tabs"][0]["name"], "Review Payment")
            self.assertEqual(document["value"]["spaces"][0]["tabs"][1]["name"], "My Custom Name")

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
        self.assertEqual(n.preferred_title(record), "Fix Checkout")
        record["labels"].pop("session.explicit-title")
        record["title"] = "Codex"
        self.assertEqual(n.preferred_title(record), "Fix Checkout")

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
