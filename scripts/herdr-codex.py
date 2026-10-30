#!/usr/bin/env python3
"""Register pane-local Codex selections while relaying the shared daemon protocol."""
import argparse
import asyncio
import json
import os
import re
import sys
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import uuid


class ThreadObserver:
    def __init__(self, register):
        self.pending = set()
        self.register = register

    def request(self, message):
        if message.get("method") in {"thread/start", "thread/resume", "thread/fork"}:
            self.pending.add(message.get("id"))

    def response(self, message):
        ident = message.get("id")
        if ident in self.pending:
            self.pending.remove(ident)
            thread = (message.get("result") or {}).get("thread") or {}
            if thread.get("id"):
                self.register(thread["id"])


def reconnect_args(args):
    # The TUI prints its remote URI on exit; our temporary relay is gone then.
    result = []
    index = 0
    while index < len(args):
        arg = args[index]
        value = args[index + 1] if arg == "--remote" and index + 1 < len(args) else arg.removeprefix("--remote=")
        if (arg == "--remote" or arg.startswith("--remote=")) and re.fullmatch(
                r"unix:///tmp/herdr-codex-[^/]+/client\.sock", value):
            index += 2 if arg == "--remote" else 1
        else:
            result.append(arg)
            index += 1
    return result


def interactive(args):
    if any(arg == "--no-daemon" or arg == "--remote" or arg.startswith("--remote=") for arg in args):
        return False
    values = {"-c", "--config", "-m", "--model", "-p", "--profile", "-C", "--cd",
              "-s", "--sandbox", "-a", "--ask-for-approval", "-i", "--image",
              "--enable", "--disable", "--add-dir", "--local-provider"}
    commands = {"agents", "exec", "review", "login", "logout", "mcp", "plugin",
                "app-server", "remote-control", "app", "completion", "update",
                "doctor", "sandbox", "debug", "apply", "queue", "archive", "delete",
                "migrate-rollouts", "unarchive", "cloud", "exec-server", "features", "help"}
    skip = False
    for arg in args:
        if skip:
            skip = False
        elif arg in {"--help", "-h", "--version", "-V"}:
            return False
        elif arg in values:
            skip = True
        elif not arg.startswith("-"):
            return arg not in commands
    return True


def register(thread_id):
    uuid.UUID(thread_id)
    request = {"id": "herdr-codex", "method": "pane.report_agent_session",
               "params": {"pane_id": os.environ["HERDR_PANE_ID"], "source": "herdr:codex",
                          "agent": "codex", "seq": time.time_ns(),
                          "agent_session_id": thread_id}}
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(2)
        client.connect(os.environ["HERDR_SOCKET_PATH"])
        client.sendall((json.dumps(request) + "\n").encode())
        reply = json.loads(client.makefile("rb").readline())
        if reply.get("error"):
            raise RuntimeError(str(reply["error"]))


async def launch(binary, args, address, backend):
    from websockets.asyncio.client import unix_connect
    from websockets.asyncio.server import unix_serve
    from websockets.exceptions import ConnectionClosed
    connected = False

    async def accept(client):
        nonlocal connected
        if connected:
            await client.close(code=1008, reason="one terminal client per pane")
            return
        connected = True
        observer = ThreadObserver(register)
        tasks = []
        try:
            async with unix_connect(backend, uri="ws://localhost/", max_size=None) as daemon:
                async def relay(source, destination, inspect):
                    async for message in source:
                        try:
                            inspect(json.loads(message))
                        except (ValueError, TypeError, KeyError, OSError, RuntimeError) as error:
                            print(f"herdr-codex: registration unavailable: {error}", file=sys.stderr)
                        await destination.send(message)
                tasks = [asyncio.create_task(relay(client, daemon, observer.request)),
                         asyncio.create_task(relay(daemon, client, observer.response))]
                done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                for task in done:
                    task.result()
        except ConnectionClosed:
            pass
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            await client.close()
            connected = False

    server = await unix_serve(accept, path=address, max_size=None)
    os.chmod(address, 0o600)
    tui = None
    try:
        tui = await asyncio.create_subprocess_exec(binary, "--remote", f"unix://{address}", *args)
        return await tui.wait()
    finally:
        if tui and tui.returncode is None:
            tui.terminate()
            await tui.wait()
        server.close()
        await server.wait_closed()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex", required=True)
    options, args = parser.parse_known_args()
    if args[:1] == ["--"]:
        args = args[1:]
    args = reconnect_args(args)
    if os.environ.get("HC_TERMINAL_ID"):
        os.environ.pop("HERDR_NATIVE_DIRECT", None)
        # Native core owns this process tree; a shared daemon would outlive close.
        for key in ("HERDR_ENV", "HERDR_PANE_ID", "HERDR_SOCKET_PATH"):
            os.environ.pop(key, None)
        if "--no-daemon" in args or interactive(args):
            os.environ["HERDR_NATIVE_DIRECT"] = "1"
        if "resume" in args:
            index = args.index("resume") + 1
            if index < len(args):
                try:
                    uuid.UUID(args[index])
                except ValueError:
                    pass
                else:
                    try:
                        subprocess.run(["herdr-native", "register", "--agent", "codex", "--session", args[index],
                                        "--terminal", os.environ["HC_TERMINAL_ID"], "--cwd", os.getcwd()],
                                       check=True, capture_output=True, timeout=10)
                    except (OSError, subprocess.SubprocessError):
                        print("herdr-codex: early core registration unavailable", file=sys.stderr)
        if interactive(args):
            args = ["--no-daemon", *args]
    if not (os.environ.get("HERDR_ENV") == "1" and os.environ.get("HERDR_PANE_ID")
            and os.environ.get("HERDR_SOCKET_PATH") and os.isatty(0) and interactive(args)):
        os.execv(options.codex, [options.codex, *args])
    # Native startup is idempotent; never stop or restart the shared daemon.
    startup = subprocess.run([options.codex, "app-server", "daemon", "start"],
                             stdout=subprocess.PIPE, text=True, check=True)
    backend = json.loads(startup.stdout)["socketPath"]
    with tempfile.TemporaryDirectory(prefix="herdr-codex-", dir="/tmp") as directory:
        try:
            return asyncio.run(launch(options.codex, args, str(Path(directory) / "client.sock"), backend))
        except KeyboardInterrupt:
            return 130


if __name__ == "__main__":
    raise SystemExit(main())
