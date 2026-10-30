import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / "scripts/herdr-codex.py"
spec = importlib.util.spec_from_file_location("bridge", path)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class RegistrationTests(unittest.TestCase):
    def test_shared_daemon_hooks_do_not_report_inherited_pane(self):
        module = (path.parents[1] / "home/herdr.nix").read_text()
        self.assertNotIn("programs.codex.hooks.SessionStart", module)
        self.assertNotIn('home.file.".codex/herdr-agent-state.sh"', module)

    def test_only_response_to_this_clients_selection_registers(self):
        seen = []
        observer = bridge.ThreadObserver(seen.append)
        observer.request({"id": 1, "method": "thread/resume"})
        observer.response({"method": "thread/started", "params": {"thread": {"id": "other"}}})
        observer.response({"id": 2, "result": {"thread": {"id": "other"}}})
        self.assertEqual(seen, [])
        observer.response({"id": 1, "result": {"thread": {"id": "ours"}}})
        self.assertEqual(seen, ["ours"])

    def test_failed_selection_and_unrelated_read_do_not_register(self):
        seen = []
        observer = bridge.ThreadObserver(seen.append)
        observer.request({"id": 1, "method": "thread/start"})
        observer.response({"id": 1, "error": {"message": "failed"}})
        observer.request({"id": 2, "method": "thread/read"})
        observer.response({"id": 2, "result": {"thread": {"id": "other"}}})
        self.assertEqual(seen, [])

    def test_switching_threads_refreshes_registration(self):
        seen = []
        observer = bridge.ThreadObserver(seen.append)
        for i, method in enumerate(("thread/start", "thread/fork", "thread/resume")):
            observer.request({"id": i, "method": method})
            observer.response({"id": i, "result": {"thread": {"id": str(i)}}})
        self.assertEqual(seen, ["0", "1", "2"])

    def test_reconnect_command_does_not_depend_on_deleted_relay_socket(self):
        args = ["--remote", "unix:///tmp/herdr-codex-test/client.sock", "resume", "id"]
        self.assertEqual(bridge.reconnect_args(args), ["resume", "id"])
        explicit = ["--remote", "unix:///tmp/another.sock", "resume", "id"]
        self.assertEqual(bridge.reconnect_args(explicit), explicit)

    def test_operational_commands_and_explicit_transports_pass_through(self):
        for args in (["queue", "--thread", "id"], ["app-server", "proxy"],
                     ["--no-daemon"], ["--remote", "unix://"], ["-c", "foo=1", "exec", "hello"]):
            self.assertFalse(bridge.interactive(args))
        for args in ([], ["resume", "id"], ["-m", "model", "resume", "id"], ["hello"]):
            self.assertTrue(bridge.interactive(args))

    def test_native_core_owns_codex_and_ignores_inherited_tui_identity(self):
        with patch.dict(bridge.os.environ, {"HC_TERMINAL_ID":"t8", "HERDR_ENV":"1", "HERDR_PANE_ID":"old", "HERDR_SOCKET_PATH":"/wrong"}), patch.object(bridge.sys,"argv",["bridge","--codex","/codex","--","resume","exact"]), patch.object(bridge.os,"execv",side_effect=RuntimeError("exec")) as execute:
            with self.assertRaisesRegex(RuntimeError,"exec"):bridge.main()
            self.assertEqual(execute.call_args.args,('/codex',['/codex','--no-daemon','resume','exact']))
            self.assertEqual(bridge.os.environ['HERDR_NATIVE_DIRECT'],'1')
            self.assertNotIn('HERDR_PANE_ID',bridge.os.environ)

    def test_native_operational_commands_remain_unchanged(self):
        with patch.dict(bridge.os.environ, {"HC_TERMINAL_ID":"t8"}), patch.object(bridge.sys,"argv",["bridge","--codex","/codex","--","queue","--thread","exact"]), patch.object(bridge.os,"execv",side_effect=RuntimeError("exec")) as execute:
            with self.assertRaisesRegex(RuntimeError,"exec"):bridge.main()
            self.assertEqual(execute.call_args.args,('/codex',['/codex','queue','--thread','exact']))


if __name__ == "__main__":
    unittest.main()
