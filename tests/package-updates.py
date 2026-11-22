import importlib.util
import pathlib
import unittest
from unittest.mock import patch

path = pathlib.Path(__file__).parents[1] / 'scripts/package-updates.py'

class Updates(unittest.TestCase):
    def test_only_changed_running_services_restart(self):
        spec = importlib.util.spec_from_file_location('updates', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with patch.object(module, 'run') as run, patch.object(module, 'services', side_effect=[{'daemon': 'old', 'same': 'v1'}, {'daemon': 'new', 'same': 'v1'}]):
            module.update('brew')
        self.assertEqual(run.call_args_list[-1].args[0], ['brew', 'services', 'restart', 'daemon'])
        self.assertEqual(run.call_count, 3)

    def test_upgrade_failure_still_restarts_updated_service_and_propagates(self):
        spec = importlib.util.spec_from_file_location('updates', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        import subprocess
        with patch.object(module, 'run', side_effect=[None, subprocess.CalledProcessError(1, 'upgrade'), None]) as run, patch.object(module, 'services', side_effect=[{'daemon': 'old'}, {'daemon': 'new'}]):
            with self.assertRaises(subprocess.CalledProcessError):
                module.update('brew')
        self.assertEqual(run.call_args_list[-1].args[0], ['brew', 'services', 'restart', 'daemon'])

if __name__ == '__main__':
    unittest.main()
