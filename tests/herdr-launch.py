"""Check native hdr routing without touching a real terminal or desktop."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/herdr-launch.sh"


class LaunchTests(unittest.TestCase):
    def test_routes(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            for name in ("core", "open"):
                path = root / name
                path.write_text('#!/bin/sh\nprintf "%s\\n" "' + name + '" "$@"\n')
                path.chmod(0o755)
            base = {k: v for k, v in os.environ.items() if k not in ("SSH_CONNECTION", "SSH_TTY", "HERDR_APP_BUNDLE")}
            base.update(PATH=str(root) + ":/usr/bin:/bin", HERDR_CORE_BIN=str(root / "core"))
            cases = [
                ({}, [], ["core", "attach"]),
                ({}, ["attach", "t9"], ["core", "attach", "t9"]),
                ({"HERDR_APP_BUNDLE": "/Applications/Test.app"}, [], ["open", "-a", "/Applications/Test.app"]),
                ({"HERDR_APP_BUNDLE": "/Applications/Test.app", "SSH_CONNECTION": "remote"}, [], ["core", "attach"]),
                ({"HERDR_APP_BUNDLE": "/Applications/Test.app", "SSH_TTY": "/dev/test"}, [], ["core", "attach"]),
                ({"HERDR_APP_BUNDLE": "/Applications/Test.app"}, ["ls"], ["core", "ls"]),
            ]
            for extra, args, expected in cases:
                with self.subTest(extra=extra, args=args):
                    result = subprocess.run(["/bin/bash", str(SCRIPT), *args], env=base | extra, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.splitlines(), expected)

    def test_mobile_menu_switches_creates_and_returns_after_detach(self):
        import json
        import pty
        import select
        import time
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            log = root / "calls"
            core = root / "core"
            core.write_text("#!/usr/bin/python3\nimport json,os,sys\nwith open(os.environ['CALLS'], 'a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')\nif sys.argv[1] == 'connect': print(json.dumps({'result':{'value':{'spaces':[{'id':'space-id'}]}}}))\nif sys.argv[1] == 'run': print(json.dumps({'address':'t9'}))\n")
            core.chmod(0o755)
            master, slave = pty.openpty()
            env = dict(os.environ, HERDR_CORE_BIN=str(core), HERDR_SPACE_ID="space-id", CALLS=str(log), SSH_TTY="/dev/test")
            proc = subprocess.Popen(["/bin/bash", str(SCRIPT), "menu"], env=env, stdin=slave, stdout=slave, stderr=slave)
            os.close(slave)
            output = b""
            try:
                os.write(master, b"s\nn\nq\n")
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if select.select([master], [], [], 0.1)[0]:
                        try:
                            output += os.read(master, 65536)
                        except OSError:
                            break
                    if proc.poll() is not None:
                        break
                self.assertIsNotNone(proc.poll(), output.decode())
                self.assertEqual(proc.returncode, 0, output.decode())
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual(calls[0], ["attach"])
                self.assertIn(["attach", "t9"], calls)
                self.assertEqual(sum(call[0] == "run" for call in calls), 1)
                self.assertGreaterEqual(output.count(b"New session"), 3)
            finally:
                if proc.poll() is None:
                    proc.kill()
                proc.wait()
                os.close(master)

    def test_phone_opens_native_core_tui(self):
        import pty
        import select
        import time
        with tempfile.TemporaryDirectory() as scratch:
            tui = Path(scratch) / "hct"
            tui.write_text('#!/bin/sh\nprintf "CORE-TUI %s\\n" "$*"\n')
            tui.chmod(0o755)
            master, slave = pty.openpty()
            env = dict(os.environ, HERDR_TUI_BIN=str(tui), SSH_TTY="/dev/test")
            proc = subprocess.Popen(["/bin/bash", str(SCRIPT)], env=env, stdin=slave, stdout=slave, stderr=slave)
            os.close(slave)
            output = b""
            try:
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    if select.select([master], [], [], 0.1)[0]:
                        try:
                            output += os.read(master, 65536)
                        except OSError:
                            break
                    if proc.poll() is not None:
                        break
                self.assertEqual(proc.poll(), 0, output.decode())
                self.assertIn(b"CORE-TUI --no-touch", output)
                self.assertNotIn(b"Choose [s/n/q]", output)
            finally:
                if proc.poll() is None:
                    proc.kill()
                proc.wait()
                os.close(master)

    def test_new_requires_explicit_space(self):
        result = subprocess.run(["/bin/bash", str(SCRIPT), "new"], env={"PATH": "/usr/bin:/bin"}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("space", result.stderr)

    def test_new_labels_terminal_then_attaches(self):
        import json
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            log = root / "calls"
            core = root / "core"
            core.write_text("#!/usr/bin/python3\nimport json,os,sys\nwith open(os.environ['CALLS'], 'a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')\nif sys.argv[1] == 'connect': print(json.dumps({'result':{'value':{'spaces':[{'id':'space-id'}]}}}))\nif sys.argv[1] == 'run': print(json.dumps({'address':'t9'}))\n")
            core.chmod(0o755)
            env = dict(os.environ, HERDR_CORE_BIN=str(core), HERDR_SPACE_ID="space-id", CALLS=str(log))
            result = subprocess.run(["/bin/bash", str(SCRIPT), "new", "codex", "--no-daemon"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            run, attach = calls[-2:]
            self.assertEqual(run, ["run", "--bg", "--json", "--no-parent", "--no-notify", "--keep", "--cwd", env["HOME"], "--label", "herdr.space=space-id", "codex", "--no-daemon"])
            self.assertEqual(attach, ["attach", "t9"])

    def test_new_refuses_stale_space(self):
        with tempfile.TemporaryDirectory() as scratch:
            core = Path(scratch) / "core"
            core.write_text("#!/bin/sh\nif [ \"$1\" = connect ]; then echo '{\"result\":{\"value\":{\"spaces\":[]}}}'; else echo 'unexpected terminal creation' >&2; exit 99; fi\n")
            core.chmod(0o755)
            result = subprocess.run(["/bin/bash", str(SCRIPT), "new"], env=dict(os.environ, HERDR_CORE_BIN=str(core), HERDR_SPACE_ID="stale"), capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("space", result.stderr)
            self.assertNotIn("unexpected terminal creation", result.stderr)

    def test_legacy_alias_remains(self):
        aliases = (SCRIPT.parent.parent / "home/aliases/ai.nix").read_text()
        self.assertIn('hdr-tui = "herdr";', aliases)
        self.assertNotIn('hdr = "herdr";', aliases)


if __name__ == "__main__":
    unittest.main()
