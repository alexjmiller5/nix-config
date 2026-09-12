#!/usr/bin/env python3
"""Run the auth entry points against a fake provider, in separate processes."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class AuthTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.token = self.root / "agent-token"
        self.token.write_text("fixture-agent")
        self.provider = self.root / "op"
        self.provider.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
auth = os.environ.get('OP_SERVICE_ACCOUNT_TOKEN', 'desktop')
data = sys.stdin.read() if os.environ.get('ECHO_INPUT') else ''
with open(os.environ['CALLS'], 'a') as f:
    f.write(json.dumps([auth, sys.argv[1:]]) + '\\n')
if sys.argv[1:2] == ['signin']:
    Path(os.environ['CALLS'] + '.signed-in').touch()
    sys.exit(0)
if auth == 'desktop' and os.environ.get('REQUIRE_SIGNIN') and not Path(os.environ['CALLS'] + '.signed-in').exists():
    print('account is not signed in', file=sys.stderr)
    sys.exit(11)
if auth == 'fixture-agent' and os.environ.get('FAIL'):
    print(os.environ['FAIL'], file=sys.stderr)
    sys.exit(7)
if auth == 'desktop' and os.environ.get('DESKTOP_FAIL'):
    print('desktop unavailable', file=sys.stderr)
    sys.exit(8)
print(auth + (':' + data if os.environ.get('ECHO_INPUT') else ''))
""")
        self.provider.chmod(0o700)
        self.cfg = self.root / "config.json"
        self.cfg.write_text(
            json.dumps(
                {
                    "op": str(self.provider),
                    "serviceAccountTokenFile": str(self.token),
                    "vaultId": "agent-vault",
                    "connect": None,
                }
            )
        )
        self.env = {
            k: v
            for k, v in os.environ.items()
            if not k.startswith(("OP_", "AGENT_", "CLAUDE", "CODEX"))
        }
        self.env.update(
            HOME=str(self.root),
            XDG_STATE_HOME=str(self.root / "state"),
            AGENT_SHELL="codex",
            CODEX_THREAD_ID="test-thread",
            CALLS=str(self.root / "calls"),
        )
        self.read = ["read", "op://agent-vault/item/token"]

    def run_auth(self, *args, stdin=None, **env):
        return subprocess.run(
            [sys.executable, str(ROOT / "scripts/op-auth.py"), str(self.cfg), *args],
            env=self.env | env,
            input=stdin,
            check=False,
            capture_output=True,
            text=True,
        )

    def calls(self):
        return [
            json.loads(line)
            for line in (self.root / "calls").read_text().splitlines()
            if json.loads(line)[1][:1] != ["signin"]
        ]

    def test_rate_limit_switches_once_and_survives_the_next_tool_call(self):
        failure = "[ERROR] could not read secret: Too many requests. Your client has been rate-limited."
        first = self.run_auth("exec", *self.read, FAIL=failure)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout.strip(), "desktop")
        second = self.run_auth("exec", *self.read, FAIL=failure)
        self.assertEqual(second.stdout.strip(), "desktop")
        self.assertEqual(
            [c[0] for c in self.calls()], ["fixture-agent", "desktop", "desktop"]
        )
        self.assertEqual(self.run_auth("status").stdout.strip(), "desktop")
        self.assertEqual(
            self.run_auth(
                "exec", *self.read, CODEX_THREAD_ID="another-thread"
            ).stdout.strip(),
            "fixture-agent",
        )
        state = list((self.root / "state/op/auth-sessions").iterdir())
        self.assertEqual([p.read_text() for p in state], ["desktop\n"])
        self.assertEqual(state[0].stat().st_mode & 0o777, 0o600)

    def test_manual_mode_preserves_explicit_project_credentials(self):
        selected = self.run_auth("desktop")
        self.assertEqual(selected.returncode, 0, selected.stderr)
        self.assertEqual(self.run_auth("exec", *self.read).stdout.strip(), "desktop")
        project = self.run_auth(
            "exec", *self.read, OP_SERVICE_ACCOUNT_TOKEN="fixture-project"
        )
        self.assertEqual(project.stdout.strip(), "fixture-project")
        self.assertEqual(
            self.run_auth(
                "personal", *self.read, OP_SERVICE_ACCOUNT_TOKEN="fixture-project"
            ).stdout.strip(),
            "desktop",
        )

    def test_other_vault_uses_user_auth_without_changing_session(self):
        result = self.run_auth("exec", "read", "op://project-vault/item/token")
        self.assertEqual(result.stdout.strip(), "desktop", result.stderr)
        self.assertEqual(self.run_auth("status").stdout.strip(), "auto")
        self.assertEqual(
            self.run_auth("exec", *self.read).stdout.strip(), "fixture-agent"
        )

    def test_unrelated_errors_and_child_commands_are_not_retried(self):
        for args, failure in [
            (self.read, "[ERROR] item not found"),
            (["run", "--", "echo", "done"], "[ERROR] (429) Too Many Requests"),
        ]:
            with self.subTest(args=args):
                before = len(self.calls()) if (self.root / "calls").exists() else 0
                result = self.run_auth("exec", *args, FAIL=failure)
                self.assertEqual(result.returncode, 7, result.stderr)
                self.assertEqual(len(self.calls()), before + 1)
                self.assertEqual(self.run_auth("status").stdout.strip(), "auto")

    def test_write_is_not_replayed_but_following_calls_use_desktop(self):
        result = self.run_auth(
            "exec", "item", "edit", "item", FAIL="[ERROR] (429) Too Many Requests"
        )
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(self.run_auth("status").stdout.strip(), "desktop")

    def test_desktop_failure_does_not_loop_or_return_to_sa(self):
        result = self.run_auth(
            "exec", *self.read, FAIL="[ERROR] (429) Too Many Requests", DESKTOP_FAIL="1"
        )
        self.assertEqual(result.returncode, 8, result.stderr)
        self.assertEqual([c[0] for c in self.calls()], ["fixture-agent", "desktop"])
        self.assertEqual(self.run_auth("status").stdout.strip(), "desktop")

    def test_global_flags_keep_vault_routing_and_child_errors_separate(self):
        result = self.run_auth(
            "exec",
            "--no-color",
            "--format=json",
            "read",
            "op://project-vault/item/token",
        )
        self.assertEqual(result.stdout.strip(), "desktop", result.stderr)
        child = self.run_auth(
            "exec",
            "--no-color",
            "run",
            "--",
            "echo",
            "done",
            FAIL="[ERROR] (429) Too Many Requests",
        )
        self.assertEqual(child.returncode, 7)
        self.assertEqual(self.run_auth("status").stdout.strip(), "auto")

    def test_retry_preserves_piped_item_input(self):
        for index, arguments in enumerate(
            [
                ["item", "get", "-"],
                ["item", "get"],
                ["item", "get", "--format=json"],
                ["vault", "get", "-"],
            ]
        ):
            with self.subTest(arguments=arguments):
                result = self.run_auth(
                    "exec",
                    *arguments,
                    "--vault",
                    "agent-vault",
                    stdin="fixture-item",
                    ECHO_INPUT="1",
                    FAIL="[ERROR] (429) Too Many Requests",
                    CODEX_THREAD_ID=f"pipe-{index}",
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "desktop:fixture-item")

    def test_desktop_auth_signs_in_before_the_requested_operation(self):
        result = self.run_auth("personal", *self.read, REQUIRE_SIGNIN="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "desktop")

    def test_child_help_flag_does_not_skip_desktop_signin(self):
        result = self.run_auth(
            "personal", "run", "--", "child", "--help", REQUIRE_SIGNIN="1"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "desktop")

    def test_background_context_without_session_does_not_escalate(self):
        result = self.run_auth(
            "exec",
            *self.read,
            CODEX_THREAD_ID="",
            AGENT_OP_SESSION="",
            FAIL="[ERROR] (429) Too Many Requests",
        )
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual([c[0] for c in self.calls()], ["fixture-agent"])

    def test_shell_initializer_honors_session_mode_and_project_override(self):
        self.assertEqual(self.run_auth("desktop").returncode, 0)
        for token, expected in [
            ("fixture-agent", ""),
            ("fixture-project", "fixture-project"),
        ]:
            result = subprocess.run(
                [
                    "sh",
                    "-c",
                    '. ./home/agent-detect.sh; . ./home/agent-op-env.sh; printf %s "${OP_SERVICE_ACCOUNT_TOKEN:-}"',
                ],
                cwd=ROOT,
                env=self.env
                | {
                    "OP_SERVICE_ACCOUNT_TOKEN": token,
                    "AGENT_OP_TOKEN_FILE": str(self.token),
                },
                text=True,
                check=False,
                capture_output=True,
            )
            self.assertEqual(result.stdout, expected, result.stderr)


if __name__ == "__main__":
    unittest.main()
