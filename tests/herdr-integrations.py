"""Smoke-test the installed SessionStart hooks without launching an agent."""

import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor


with tempfile.TemporaryDirectory(prefix="herdr-hooks-", dir="/tmp") as directory:
    socket_path = str(Path(directory) / "hook.sock")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(socket_path)
        server.listen()
        server.settimeout(3)

        def receive():
            connection, _ = server.accept()
            with connection:
                message = json.loads(connection.makefile().readline())
                connection.sendall(b'{"result":{}}\n')
                return message

        for agent, settings in (
            ("claude", Path.home() / ".claude/settings.json"),
            ("codex", Path.home() / ".codex/hooks.json"),
        ):
            groups = json.loads(settings.read_text())["hooks"]["SessionStart"]
            hooks = [
                hook["command"]
                for group in groups
                for hook in group["hooks"]
                if "herdr-agent-state.sh" in hook.get("command", "")
            ]
            assert len(hooks) == 1, f"{agent}: expected one Herdr SessionStart hook"
            environment = {
                **os.environ,
                "HERDR_ENV": "1",
                "HERDR_SOCKET_PATH": socket_path,
                "HERDR_PANE_ID": "p1",
                "CODEX_THREAD_ID": "test-session",
            }
            event = json.dumps({
                "hook_event_name": "SessionStart",
                "session_id": "test-session",
                "transcript_path": str(Path(directory) / "transcript.jsonl"),
                "source": "startup",
            })
            with ThreadPoolExecutor(max_workers=1) as pool:
                incoming = pool.submit(receive)
                subprocess.run(hooks[0], shell=True, input=event, text=True,
                               env=environment, check=True, timeout=5)
                message = incoming.result()
            assert message["method"] == "pane.report_agent_session"
            assert message["params"]["agent"] == agent
            assert message["params"]["agent_session_id"] == "test-session"
            assert message["params"]["pane_id"] == "p1"
            print(f"{agent}: installed hook reports the conversation to Herdr")
