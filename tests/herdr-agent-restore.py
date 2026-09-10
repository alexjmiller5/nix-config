"""Exercise the patched plugin against an isolated real Herdr server.

Run: python3 tests/herdr-agent-restore.py <plugin-source>
Only the external agent executables are stand-ins; they log resume arguments.
"""

import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

plugin = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(plugin))
from herdr_undo_close.api import HerdrApi


def wait_for(check, description):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        try:
            result = check()
            if result:
                return result
        except (OSError, ValueError):
            pass
        time.sleep(0.1)
    raise AssertionError(description)


def exited(pid):
    try:
        os.kill(pid, 0)
        return False
    except ProcessLookupError:
        return True


with tempfile.TemporaryDirectory(prefix="herdr-test-", dir="/tmp") as temp:
    root = Path(temp)
    shell = shutil.which("sh")
    herdr = shutil.which("herdr")
    bin_dir = root / "bin"
    bin_dir.mkdir()
    for agent in ("claude", "codex"):
        executable = bin_dir / agent
        executable.write_text(
            f"#!{shell}\n"
            f"printf '%s\\n' \"$@\" > {shlex.quote(str(root / (agent + '.argv')))}\n"
            f"exec {shlex.quote(shutil.which('sleep'))} 300\n"
        )
        executable.chmod(0o755)
    env = {
        "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
        "HOME": temp,
        "XDG_CONFIG_HOME": str(root / "config"),
        "XDG_STATE_HOME": str(root / "state"),
        "TERM": "xterm-256color",
    }
    conf = root / "config/herdr"
    conf.mkdir(parents=True)
    (conf / "config.toml").write_text(
        f"onboarding = false\n[terminal]\ndefault_shell = {json.dumps(shell)}\n"
        "shell_login = false\n[updates]\ncheck_on_start = false\n"
    )
    plugin_config = conf / "plugins/config/undo-close"
    plugin_config.mkdir(parents=True)
    (plugin_config / "config.json").write_text('{"undo_panes":false}')
    server = subprocess.Popen(
        [herdr, "server"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    api = HerdrApi(str(conf / "herdr.sock"))
    state_file = root / "state/herdr/plugins/undo-close/state.json"
    try:
        wait_for(lambda: (conf / "herdr.sock").exists(), "server socket")
        workspace = api.call("workspace.create", {"cwd": temp, "focus": True})
        workspace_id = workspace["workspace"]["workspace_id"]
        api.call("plugin.link", {"path": str(plugin)})
        for agent, resume in (("claude", "-r"), ("codex", "resume")):
            for session in (
                "11111111-1111-4111-8111-111111111111",
                "22222222-2222-4222-8222-222222222222",
            ):
                tab = api.call(
                    "tab.create",
                    {"workspace_id": workspace_id, "cwd": temp, "focus": True},
                )
                pane = tab["root_pane"]
                tab_id, pane_id = pane["tab_id"], pane["pane_id"]
                wait_for(
                    lambda tab_id=tab_id: (
                        state_file.exists()
                        and tab_id in json.loads(state_file.read_text())["index"]
                    ),
                    "initial tab capture",
                )
                pid = api.call("pane.process_info", {"pane_id": pane_id})[
                    "process_info"
                ]["shell_pid"]
                api.call(
                    "pane.report_agent",
                    {
                        "pane_id": pane_id,
                        "source": "restore-test",
                        "agent": agent,
                        "state": "idle",
                    },
                )
                api.call(
                    "pane.report_agent_session",
                    {
                        "pane_id": pane_id,
                        "source": "herdr:" + agent,
                        "agent": agent,
                        "agent_session_id": session,
                        "session_start_source": "startup",
                        "seq": 1,
                    },
                )
                context = {
                    "workspace_id": workspace_id,
                    "tab_id": tab_id,
                    "focused_pane_id": pane_id,
                }
                if agent == "claude" and session.startswith("1111"):
                    api.call("tab.close", {"tab_id": workspace["tab"]["tab_id"]})
                api.call(
                    "plugin.action.invoke",
                    {
                        "plugin_id": "undo-close",
                        "action_id": "close-tab",
                        "context": context,
                    },
                )
                wait_for(
                    lambda pid=pid: exited(pid), "closing must stop the old process"
                )
                wait_for(
                    lambda tab_id=tab_id: any(
                        c["tab_id"] == tab_id
                        for c in json.loads(state_file.read_text())["closed"]
                    ),
                    "closed tab capture",
                )
                closed = next(
                    c
                    for c in json.loads(state_file.read_text())["closed"]
                    if c["tab_id"] == tab_id
                )
                assert closed["panes"][0]["relaunch"]["session_id"] == session
                api.call(
                    "plugin.action.invoke",
                    {
                        "plugin_id": "undo-close",
                        "action_id": "reopen-last",
                        "context": {"workspace_id": workspace_id},
                    },
                )
                wait_for(
                    lambda agent=agent, resume=resume, session=session: (
                        (root / (agent + ".argv")).read_text().splitlines()
                        == [resume, session]
                    ),
                    "resume must target the exact conversation",
                )
                workspace_id = api.call("workspace.list")["workspaces"][0][
                    "workspace_id"
                ]
                print(
                    f"PASS: {agent} close stops the process; reopen passes the exact session ID",
                    flush=True,
                )
    finally:
        subprocess.run(
            [herdr, "server", "stop"],
            env=env,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        server.wait(timeout=10)
