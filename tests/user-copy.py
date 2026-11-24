import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "home/user-copy.sh"


class ClipboardTests(unittest.TestCase):
    def run_copy(self, host="local", failed=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for command in ("pbcopy", "ssh"):
                file = root / command
                file.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$CALLS\"\ncat > \"$PAYLOAD\"\nexit \"${FAILURE:-0}\"\n")
                file.chmod(0o755)
            env = dict(os.environ, PATH=tmp+":"+os.environ["PATH"], USER_CLIPBOARD_HOST=host,
                       CALLS=str(root/"calls"), PAYLOAD=str(root/"payload"), FAILURE="17" if failed else "0")
            data = "Unicode café\nquotes ' \" $ and trailing newlines\n\n".encode()
            result = subprocess.run(["bash", str(SCRIPT)], input=data, env=env, capture_output=True)
            return result, (root/"payload").read_bytes() if (root/"payload").exists() else None, (root/"calls").read_text() if (root/"calls").exists() else "", data

    def test_local_preserves_bytes(self):
        result, payload, calls, data = self.run_copy()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(payload, data)
        self.assertEqual(calls.strip(), "")
        self.assertEqual(result.stdout, b"")

    def test_remote_uses_bounded_noninteractive_ssh(self):
        result, payload, calls, data = self.run_copy("laptop.example")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(payload, data)
        self.assertEqual(calls.splitlines(), ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "laptop.example", "/usr/bin/pbcopy"])

    def test_remote_failure_does_not_fall_back(self):
        result, _, _, _ = self.run_copy("laptop.example", True)
        self.assertEqual(result.returncode, 17)

    def test_rejects_option_as_host(self):
        result, payload, _, _ = self.run_copy("-oProxyCommand=bad")
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(payload)


if __name__ == "__main__":
    unittest.main()
