#!/usr/bin/env python3
"""Shared operator authentication, with session-local desktop failover."""

import json
import os
import re
import runpy
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit


def session_file(env):
    session = (
        env.get("CODEX_THREAD_ID")
        or env.get("CODEX_SESSION_ID")
        or env.get("AGENT_OP_SESSION")
    )
    if not session:
        return None
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,160}", session):
        raise RuntimeError("Invalid agent auth session identifier")
    state = Path(env.get("XDG_STATE_HOME") or Path(env["HOME"]) / ".local/state")
    return state / "op/auth-sessions" / session


def desktop_selected(env):
    path = session_file(env)
    return env.get("AGENT_OP_AUTH") == "desktop" or bool(path and path.is_file())


def select_desktop(env):
    path = session_file(env)
    if path is None:
        raise RuntimeError(
            "No agent session ID; start a new agent session or use op-personal for this command"
        )
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.parent.chmod(0o700)
    # Exclusive creation is atomic across concurrent calls. This file holds
    # only a mode, never a token, account identity or secret.
    try:
        with open(
            path, "x", opener=lambda p, flags: os.open(p, flags, 0o600)
        ) as stream:
            stream.write("desktop\n")
    except FileExistsError:
        pass


def option(args, name):
    for index, arg in enumerate(args):
        if arg == "--":
            break
        if arg.startswith(name + "="):
            return arg.split("=", 1)[1]
        if arg == name and index + 1 < len(args):
            return args[index + 1]
    return None


def command_args(args):
    # Parse only the CLI's global flags; unknown syntax stays native and
    # cannot accidentally enable retries of a launched command.
    values = {"--account", "--config", "--encoding", "--format", "--session"}
    switches = {
        "--cache",
        "--debug",
        "--iso-timestamps",
        "--no-color",
        "--help",
        "-h",
        "--version",
        "-v",
    }
    index = 0
    while index < len(args) and args[index].startswith("-"):
        key = args[index].split("=", 1)[0]
        if key == "--":
            return args[index + 1 :] + args[:index]
        if key in values:
            index += 1 if "=" in args[index] else 2
        elif key in switches:
            index += 1
        else:
            return []
    return args[index:] + args[:index]


def user_env(env):
    result = env.copy()
    for key in ("OP_SERVICE_ACCOUNT_TOKEN", "OP_CONNECT_HOST", "OP_CONNECT_TOKEN"):
        result.pop(key, None)
    result["AGENT_OP_AUTH"] = "desktop"
    session = Path(env["HOME"]) / ".local/state/op/personal-session"
    if not result.get("OP_SESSION") and session.is_file():
        result["OP_SESSION"] = session.read_text().strip()
    return result


def auth_env(args, env, cfg, personal=False):
    result = env.copy()
    token_file = Path(env.get("AGENT_OP_TOKEN_FILE") or cfg["serviceAccountTokenFile"])
    agent_token = token_file.read_text().strip() if token_file.is_file() else ""
    supplied = env.get("OP_SERVICE_ACCOUNT_TOKEN", "")
    external = bool(
        (supplied and supplied != agent_token)
        or env.get("OP_CONNECT_HOST")
        or env.get("OP_CONNECT_TOKEN")
    )
    explicit_user = (
        option(args, "--account") or option(args, "--session") or env.get("OP_SESSION")
    )
    if personal or env.get("AGENT_OP_AUTH") == "desktop" or explicit_user:
        return user_env(result), False
    if external or not env.get("AGENT_SHELL"):
        return result, False
    if desktop_selected(env):
        return user_env(result), False
    command = command_args(args)
    vault = option(args, "--vault")
    if command[:1] == ["read"]:
        vault = next(
            (urlsplit(arg).netloc for arg in command[1:] if arg.startswith("op://")),
            vault,
        )
    if vault and cfg["vaultId"] and vault != cfg["vaultId"]:
        return user_env(result), False
    if agent_token:
        result["OP_SERVICE_ACCOUNT_TOKEN"] = agent_token
    if cfg.get("connect"):
        connect = runpy.run_path(cfg["connect"]["helper"])
        result = connect["command_env"](command, result, cfg["connect"])
    return result, bool(
        agent_token
        and result.get("OP_SERVICE_ACCOUNT_TOKEN") == agent_token
        and session_file(env) is not None
    )


def execute(args, env, cfg, personal=False):
    child, automatic = auth_env(args, env, cfg, personal)
    # A launched command can have side effects and its own unrelated 429.
    # Preserve stdin/stdout, signals and exit status through exec.
    command = command_args(args)
    if not automatic or not command or command[:1] in [["run"], ["plugin"]]:
        os.execve(cfg["op"], [cfg["op"], *args], child)
    read_only = command[:1] == ["read"] or command[:2] in [
        ["item", "get"],
        ["item", "list"],
        ["document", "get"],
        ["vault", "get"],
        ["vault", "list"],
    ]
    piped = command[:2] in [["item", "get"], ["vault", "get"]]
    input_data = sys.stdin.buffer.read() if piped and not sys.stdin.isatty() else None
    result = subprocess.run(
        [cfg["op"], *args],
        env=child,
        check=False,
        input=input_data,
        stdout=subprocess.PIPE if read_only else None,
        stderr=subprocess.PIPE,
    )
    quota = result.returncode and re.search(
        rb"(?s)\[ERROR\].*(?:Too [Mm]any [Rr]equests|rate-limited)", result.stderr
    )
    if quota:
        # Do not reattempt the exhausted SA, even when desktop auth fails.
        try:
            select_desktop(env)
        except RuntimeError as error:
            print(f"op-auth: {error}", file=sys.stderr)
        print(
            "op-auth: 1Password service-account quota reached; using desktop auth for this session.",
            file=sys.stderr,
        )
        if read_only:
            result = subprocess.run(
                [cfg["op"], *args],
                env=user_env(child),
                check=False,
                input=input_data,
                capture_output=True,
            )
        else:
            print(
                "op-auth: the write was not repeated. Check its result before rerunning it.",
                file=sys.stderr,
            )
    if result.stdout:
        sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


def main():
    cfg = json.loads(Path(sys.argv[1]).read_text())
    action, *args = sys.argv[2:]
    if action == "desktop" and not args:
        select_desktop(os.environ)
        print("Desktop auth selected for this agent session.")
    elif action == "status" and not args:
        print("desktop" if desktop_selected(os.environ) else "auto")
    elif action in ("exec", "personal"):
        return execute(args, os.environ, cfg, personal=action == "personal")
    else:
        raise RuntimeError(
            "Usage: op-auth {status|desktop}; op-personal <op arguments>"
        )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"op-auth: {error}", file=sys.stderr)
        sys.exit(1)
