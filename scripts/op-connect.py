#!/usr/bin/env python3
"""Local Connect startup and an in-memory token handoff for short-lived shells."""

import fcntl
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
from urllib.parse import urlsplit


def flag(args, name):
    for i, arg in enumerate(args):
        if arg.startswith(name + "="):
            return arg.split("=", 1)[1]
        if arg == name and i + 1 < len(args):
            return args[i + 1]
    return None


def wants_connect(args, env, cfg):
    if (env.get("AGENT_OP_AUTH") == "desktop" or not env.get("AGENT_SHELL")
            or env.get("OP_CONNECT_HOST") or env.get("OP_CONNECT_TOKEN")
            or flag(args, "--account") or flag(args, "--session")):
        return False
    # An explicitly selected project SA must never inherit agent-vault access.
    try:
        agent_token = Path(cfg["serviceAccountTokenFile"]).read_text().strip()
    except OSError:
        return False
    if not agent_token or env.get("OP_SERVICE_ACCOUNT_TOKEN") != agent_token:
        return False
    if args[:1] == ["read"]:
        refs = [arg for arg in args[1:] if arg.startswith("op://")]
        return len(refs) == 1 and urlsplit(refs[0]).netloc == cfg["vaultId"]
    return (args[:2] == ["item", "get"]
            and flag(args, "--vault") == cfg["vaultId"]
            and flag(args, "--format") == "json")


def command_env(args, env, cfg):
    result = env.copy()
    if env.get("AGENT_OP_AUTH") == "desktop":
        for key in ("OP_CONNECT_HOST", "OP_CONNECT_TOKEN", "OP_SERVICE_ACCOUNT_TOKEN"):
            result.pop(key, None)
    if wants_connect(args, result, cfg):
        try:
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(5)
                client.connect(str(Path(cfg["stateDirectory"]) / "token.sock"))
                chunks = []
                while chunk := client.recv(16384):
                    chunks.append(chunk)
                token = b"".join(chunks).decode()
                if not token:
                    raise OSError("empty token")
        except OSError as exc:
            raise RuntimeError(
                "Connect token service is unavailable. Start it with `op-connect-start`; "
                "for direct user authentication select AGENT_OP_AUTH=desktop."
            ) from exc
        result["OP_CONNECT_HOST"] = cfg["host"]
        result["OP_CONNECT_TOKEN"] = token
        result.pop("OP_SERVICE_ACCOUNT_TOKEN", None)
    return result


def cloud_env(cfg):
    env = os.environ.copy()
    for key in ("OP_CONNECT_HOST", "OP_CONNECT_TOKEN", "AGENT_OP_AUTH"):
        env.pop(key, None)
    env["OP_SERVICE_ACCOUNT_TOKEN"] = Path(cfg["serviceAccountTokenFile"]).read_text().strip()
    if not env["OP_SERVICE_ACCOUNT_TOKEN"]:
        raise RuntimeError("Agent service-account token file is empty")
    return env


def cloud_op(cfg, env, *args):
    result = subprocess.run([cfg["op"], *args], env=env, capture_output=True, text=True)
    if result.returncode:
        # op's read/document diagnostics contain no returned secret values.
        raise RuntimeError(result.stderr.strip() or "1Password bootstrap failed")
    return result.stdout.strip()


def wait_for_docker(cfg):
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        try:
            result = subprocess.run([cfg["docker"], "info"], stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, timeout=10)
            if result.returncode == 0:
                return
        except subprocess.TimeoutExpired:
            pass  # Docker can accept a connection before the engine is ready.
        time.sleep(2)
    raise RuntimeError("Docker did not start; check Docker Desktop's setup dialog")


def serve(cfg):
    os.umask(0o077)
    state = Path(cfg["stateDirectory"])
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    with (state / "service.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Connect token service is already running") from None
        # Wait for the existing login bootstrap to write the SA, without op polling.
        deadline = time.monotonic() + 120
        while not Path(cfg["serviceAccountTokenFile"]).is_file():
            if time.monotonic() > deadline:
                raise RuntimeError("Agent service-account token file is missing")
            time.sleep(2)
        env = cloud_env(cfg)
        credentials = state / "1password-credentials.json"
        if not credentials.exists():
            document = cloud_op(cfg, env, "document", "get", cfg["credentialsItemId"],
                                "--vault", cfg["vaultId"])
            json.loads(document)
            temporary = state / ".credentials.tmp"
            temporary.write_text(document)
            temporary.chmod(0o600)
            temporary.replace(credentials)
        credentials.chmod(0o600)
        # Exactly one token read per service start. It never enters Docker metadata.
        token = cloud_op(cfg, env, "read", cfg["tokenOpRef"]).encode()
        del env
        if not token:
            raise RuntimeError("Connect token is empty")
        subprocess.run(["/usr/bin/open", "-g", "-j", "-a", cfg["dockerApp"]], check=True)
        wait_for_docker(cfg)
        subprocess.run([cfg["docker"], "compose", "-f", cfg["composeFile"], "up", "-d"],
                       check=True)
        path = state / "token.sock"
        path.unlink(missing_ok=True)
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(path))
            path.chmod(0o600)
            server.listen(16)
            print("Connect containers started; local token service ready", flush=True)
            while True:
                client, _ = server.accept()
                with client:
                    client.settimeout(2)
                    try:
                        client.sendall(token)
                    except OSError:
                        pass  # A caller can exit before receiving its token.


def main():
    cfg = json.loads(Path(sys.argv[1]).read_text())
    action, *args = sys.argv[2:]
    if action == "serve":
        serve(cfg)
    elif action == "exec":
        os.execve(cfg["op"], [cfg["op"], *args], command_env(args, os.environ, cfg))
    else:
        raise RuntimeError("Expected serve or exec")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"op-connect: {error}", file=sys.stderr)
        sys.exit(1)
