#!/usr/bin/env python3
"""Exercise routing and the local token handoff without real credentials."""

import importlib.util
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import contextlib
import io
import json

spec = importlib.util.spec_from_file_location(
    "connect", Path(__file__).resolve().parents[1] / "scripts/op-connect.py"
)
connect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(connect)
bootstrap_spec = importlib.util.spec_from_file_location(
    "bootstrap", Path(__file__).resolve().parents[1] / "scripts/op-connect-bootstrap.py"
)
bootstrap = importlib.util.module_from_spec(bootstrap_spec)
bootstrap_spec.loader.exec_module(bootstrap)


class ConnectTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name)
        self.sa = self.state / "agent-sa-token"
        self.sa.write_text("fixture-agent-token")
        self.cfg = {
            "vaultId": "fixture-vault",
            "stateDirectory": str(self.state),
            "serviceAccountTokenFile": str(self.sa),
            "host": "http://127.0.0.1:8080",
        }
        self.env = {
            "AGENT_SHELL": "codex",
            "OP_SERVICE_ACCOUNT_TOKEN": "fixture-agent-token",
        }
        self.read = ["read", "op://fixture-vault/item/credential"]

    def test_agent_reads_use_connect(self):
        self.assertTrue(connect.wants_connect(self.read, self.env, self.cfg))
        self.assertTrue(connect.wants_connect(
            ["item", "get", "item", "--vault=fixture-vault", "--format=json"],
            self.env, self.cfg,
        ))

    def test_other_auth_and_operations_stay_direct(self):
        for args, overrides in [
            (self.read, {"AGENT_OP_AUTH": "desktop"}),
            (self.read, {"OP_SERVICE_ACCOUNT_TOKEN": "fixture-project-token"}),
            (self.read, {"AGENT_SHELL": ""}),
            (self.read, {"OP_CONNECT_HOST": "https://caller.example"}),
            (["--account", "other", *self.read], {}),
            ([*self.read, "--session=explicit"], {}),
            (["read", "op://other-vault/item/credential"], {}),
            (["item", "edit", "item", "--vault", "fixture-vault"], {}),
            (["item", "get", "item", "--vault", "fixture-vault"], {}),
            (["document", "get", "item", "--vault", "fixture-vault"], {}),
            (["connect", "server", "list"], {}),
        ]:
            with self.subTest(args=args, overrides=overrides):
                self.assertFalse(connect.wants_connect(args, self.env | overrides, self.cfg))

    def test_dead_service_does_not_fall_back_to_cloud(self):
        with self.assertRaisesRegex(RuntimeError, "Connect token service is unavailable"):
            connect.command_env(self.read, self.env, self.cfg)

    def test_token_is_delivered_only_to_op_environment(self):
        path = self.state / "token.sock"
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(path))
            server.listen(1)

            def send():
                client, _ = server.accept()
                with client:
                    client.sendall(b"fixture-connect-token")

            worker = threading.Thread(target=send)
            worker.start()
            env = connect.command_env(self.read, self.env, self.cfg)
            worker.join(2)
        self.assertEqual(env["OP_CONNECT_TOKEN"], "fixture-connect-token")
        self.assertEqual(env["OP_CONNECT_HOST"], self.cfg["host"])
        self.assertNotIn("OP_CONNECT_TOKEN", self.env)
        self.assertNotIn("OP_SERVICE_ACCOUNT_TOKEN", env)
        self.assertEqual(sorted(p.name for p in self.state.iterdir()),
                         ["agent-sa-token", "token.sock"])

    def test_desktop_clears_inherited_connect_and_sa(self):
        env = connect.command_env(self.read, self.env | {
            "AGENT_OP_AUTH": "desktop", "OP_CONNECT_TOKEN": "old", "OP_CONNECT_HOST": "old",
        }, self.cfg)
        self.assertFalse(any(k.startswith("OP_CONNECT_") for k in env))
        self.assertNotIn("OP_SERVICE_ACCOUNT_TOKEN", env)

    def test_bootstrap_cloud_environment_cannot_loop_through_connect(self):
        with patch.dict(os.environ, {
            "OP_CONNECT_TOKEN": "old", "OP_CONNECT_HOST": "old", "AGENT_OP_AUTH": "desktop",
        }, clear=True):
            env = connect.cloud_env(self.cfg)
        self.assertEqual(env["OP_SERVICE_ACCOUNT_TOKEN"], "fixture-agent-token")
        self.assertNotIn("OP_CONNECT_TOKEN", env)
        self.assertNotIn("AGENT_OP_AUTH", env)

    def test_provisioning_handles_cli_output_and_keeps_token_out_of_argv(self):
        items, servers, calls = [], [], []

        def run(args, **kwargs):
            calls.append(args)
            self.assertNotIn("OP_SERVICE_ACCOUNT_TOKEN", kwargs["env"])
            self.assertNotIn("OP_CONNECT_TOKEN", kwargs["env"])
            command = args[1:4]
            result = ""
            if command[:2] == ["item", "list"]:
                result = json.dumps(items)
            elif command == ["connect", "server", "list"]:
                result = json.dumps(servers)
            elif command == ["connect", "server", "create"]:
                servers.append({"id": "server-id", "name": "fixture-server"})
                (self.state / "1password-credentials.json").write_text('{"encCredentials":"fixture"}')
                result = "Server created. Credentials written to 1password-credentials.json."
            elif command[:2] == ["document", "create"]:
                items.append({"id": "document-id", "title": "Fixture op Connect Credentials"})
                result = '{"uuid":"document-id"}'
            elif command == ["connect", "token", "create"]:
                self.assertIn("fixture-vault,r", args)
                result = "fixture-connect-token"
            elif command[:2] == ["item", "create"]:
                item = json.loads(kwargs["input"])
                self.assertEqual(item["fields"][0]["value"], "fixture-connect-token")
                self.assertIn("Highly Sensitive", item["tags"])
                items.append({"id": "token-id", "title": item["title"]})
                result = '{"id":"token-id"}'
            else:
                self.fail(f"Unexpected provisioning operation: {command}")
            return subprocess.CompletedProcess(args, 0, result, "")

        argv = ["bootstrap", "--vault", "fixture-vault", "--server", "fixture-server",
                "--owner", "Fixture", "--state-directory", str(self.state)]
        with patch.object(sys, "argv", argv), patch.object(bootstrap.subprocess, "run", run):
            for attempt in range(2):
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    bootstrap.main()
                self.assertEqual(json.loads(output.getvalue())["tokenOpRef"],
                                 "op://fixture-vault/token-id/credential")
                self.assertNotIn("fixture-connect-token", output.getvalue())
        self.assertEqual(sum(args[1:4] == ["connect", "token", "create"] for args in calls), 1)
        self.assertFalse(any("fixture-connect-token" in arg for args in calls for arg in args))


if __name__ == "__main__":
    unittest.main()
