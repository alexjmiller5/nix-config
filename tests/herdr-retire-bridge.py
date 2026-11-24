"""Retirement stops only the obsolete viewer and its verified synchronizer."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/herdr-retire-bridge.sh'

class RetirementTests(unittest.TestCase):
    def run_case(self, artifacts, matching):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            state = root / 'state'
            state.mkdir()
            config, plist, log = root / 'config', root / 'plist', root / 'calls'
            watcher = subprocess.Popen(['/bin/sleep', '30'])
            try:
                if artifacts:
                    config.touch()
                    plist.touch()
                    (state / 'sync.pid').write_text(str(watcher.pid))
                for name, body in {
                    'launchctl': 'echo "launchctl $*" >> "$CALLS"; if [ "$1" = print ]; then [ "$SERVICE_PRESENT" = 1 ]; fi',
                    'herdr': 'echo "herdr $*" >> "$CALLS"; case "$*" in *"plugin list") echo "- barnuri.hc-attach (hc attach) enabled";; "plugin unlink"*) exit 1;; esac',
                    'ps': 'printf "%s\\n" "$PROCESS_COMMAND"',
                }.items():
                    f = root / name
                    f.write_text('#!/bin/sh\n' + body + '\n')
                    f.chmod(0o755)
                env = dict(os.environ, PATH=str(root) + ':/usr/bin:/bin', CALLS=str(log), SERVICE_PRESENT='1' if artifacts else '0',
                           PROCESS_COMMAND='node /nix/store/fixture-herdr-hc-attach-0.1/bin/sync.js' if matching else 'herdr-core server')
                result = subprocess.run(['/bin/bash', str(SCRIPT), str(state), str(config), str(plist)], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = log.read_text() if log.exists() else ''
                if artifacts:
                    self.assertIn('herdr --session core plugin unlink barnuri.hc-attach', calls)
                    self.assertIn('herdr --session core server stop', calls)
                    self.assertNotIn('herdr-core server', calls)
                    self.assertIn('launchctl bootout gui/', calls)
                    if matching:
                        self.assertEqual(watcher.wait(timeout=2), -15)
                    else:
                        self.assertIsNone(watcher.poll(), 'An unrelated process was signaled')
                    self.assertFalse((state / 'sync.pid').exists())
                else:
                    self.assertNotIn('herdr ', calls)
                    self.assertIsNone(watcher.poll())
            finally:
                if watcher.poll() is None:
                    watcher.terminate()
                watcher.wait()

    def test_verified_watcher_is_stopped(self):
        self.run_case(True, True)

    def test_reused_pid_cannot_stop_core(self):
        self.run_case(True, False)

    def test_native_only_install_is_unchanged(self):
        self.run_case(False, False)

if __name__ == '__main__':
    unittest.main()
