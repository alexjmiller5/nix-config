"""Exercise the real recipe with command stubs; never build or activate."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
JUST = shutil.which("just")


class SwitchLaptop(unittest.TestCase):
    def test_flags_reach_both_build_boundaries(self):
        for flags in (
            [],
            ["--max-jobs", "1", "--cores", "1"],
            ["--option", "substituters", "https://one.example.test https://two.example.test"],
        ):
            with self.subTest(flags=flags), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "justfile").write_text((ROOT / "justfile").read_text())
                log = root / "commands.jsonl"
                stub = (
                    f"#!{sys.executable}\n"
                    "import json, os, pathlib, sys\n"
                    "with open(os.environ['COMMAND_LOG'], 'a') as out:\n"
                    "    out.write(json.dumps([pathlib.Path(sys.argv[0]).name, *sys.argv[1:]]) + '\\n')\n"
                )
                for name in ("nix", "sudo", "just"):
                    path = root / name
                    path.write_text(stub)
                    path.chmod(0o755)
                result = subprocess.run(
                    [JUST, "--justfile", str(root / "justfile"), "--", "switch-laptop", *flags],
                    cwd=root,
                    env=os.environ | {"PATH": f"{root}:{os.environ['PATH']}", "COMMAND_LOG": str(log)},
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual(calls[:2], [
                    ["just", "manual"],
                    ["nix", "build", ".#darwinConfigurations.macbook-air.system", *flags],
                ])
                self.assertEqual(len(calls), 3)
                self.assertEqual(calls[2][0], "sudo")
                self.assertEqual(Path(calls[2][1]).name, "darwin-rebuild")
                self.assertEqual(calls[2][2:], ["switch", "--flake", ".#macbook-air", *flags])


if __name__ == "__main__":
    unittest.main()
