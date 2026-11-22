import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('updates', Path(__file__).parents[1] / 'scripts/system-updates.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class Updates(unittest.TestCase):
    def test_build_failure_never_pushes_or_switches_or_records_success(self):
        calls = []
        def run(args, *rest):
            calls.append(args)
            if args[:2] == ['nix', 'build']:
                raise subprocess.CalledProcessError(1, args)
            return subprocess.CompletedProcess(args, 0, stdout='example-origin\n')
        with tempfile.TemporaryDirectory() as tmp, patch.object(m, 'run', side_effect=run):
            with self.assertRaises(subprocess.CalledProcessError):
                m.update(Path(tmp), 'test-host', Path(tmp) / 'state')
            self.assertFalse((Path(tmp) / 'state/last-success').exists())
        self.assertFalse(any(c[0] == 'sudo' or c[:2] == ['git', 'push'] for c in calls))

    def test_recent_success_skips_every_command(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(m, 'run') as run:
            state = Path(tmp)
            (state / 'last-success').write_text('success')
            m.update(state, 'test-host', state)
            run.assert_not_called()

    def test_push_failure_never_switches(self):
        calls = []
        def run(args, *rest):
            calls.append(args)
            if args[:2] == ['git', 'push']:
                raise subprocess.CalledProcessError(1, args)
            return subprocess.CompletedProcess(args, 0, stdout='changed\n')
        with tempfile.TemporaryDirectory() as tmp, patch.object(m, 'run', side_effect=run):
            with self.assertRaises(subprocess.CalledProcessError):
                m.update(Path(tmp), 'test-host', Path(tmp) / 'state')
        self.assertFalse(any(c[0] == 'sudo' for c in calls))

if __name__ == '__main__':
    unittest.main()
