"""Fixture test for scripts/herdr-takeover.py.

A fake `herdr` on PATH logs every call and answers canned JSON, so the test
pins the exact tab-create / agent-start sequence the mirror of a session.json
turns into: live sessions and unmirrored transcripts are skipped, unnamed
panes get a name from the tab label, name clashes get a suffix, a cwd that
does not exist here falls back to HOME, and --dry-run touches nothing.

Run: python3 tests/herdr-takeover.py
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
script = repo / "scripts/herdr-takeover.py"

FAKE_HERDR = r"""#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_LOG"
case "$1 $2" in
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w9","focused":false},{"workspace_id":"w1","focused":true}]}}' ;;
  "agent list") echo '{"result":{"agents":[{"name":"live-one","agent_session":{"agent":"claude","value":"aaaa"}}]}}' ;;
  "tab create") n=$(wc -l < "$HERDR_LOG" | tr -d " "); echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w1:p$n\"}}}" ;;
  "agent start") echo '{"result":{}}' ;;
  *) echo "unexpected herdr call: $*" >&2; exit 1 ;;
esac
"""


def pane(cwd, name, sid):
    return {
        "cwd": cwd,
        "agent_name": name,
        "managed_agent_kind": "claude" if name else None,
        "agent_session": {"source": "herdr:claude", "agent": "claude", "kind": "id", "value": sid},
    }


def tab(label, panes):
    return {"custom_name": label, "layout": {"Pane": 1}, "panes": panes, "focused": 1, "root_pane": 1}


def run(home, log, session_file, projects, *args):
    log.write_text("")
    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{home / 'bin'}{os.pathsep}{os.environ['PATH']}",
        "HERDR_LOG": str(log),
    }
    return subprocess.run(
        [sys.executable, str(script), "--session-file", str(session_file), "--projects", str(projects), *args],
        env=env, capture_output=True, text=True, check=True,
    ).stdout


with tempfile.TemporaryDirectory() as tmp:
    home = Path(tmp)
    (home / "bin").mkdir()
    fake = home / "bin/herdr"
    fake.write_text(FAKE_HERDR)
    fake.chmod(0o755)
    log = home / "herdr.log"
    repo_dir = home / "repo"
    repo_dir.mkdir()
    projects = home / "projects"
    for sid in ("aaaa", "bbbb", "cccc", "eeee", "ffff"):
        d = projects / "-slug"
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{sid}.jsonl").write_text("{}\n")
    session_file = home / "session.json"
    session_file.write_text(json.dumps({
        "version": 3,
        "workspaces": [{"id": "w1", "tabs": [
            tab("Live One", {"1": pane("/", "live-one", "aaaa")}),
            tab("Bookmark Sync", {"2": pane(str(repo_dir), "bookmark-sync", "bbbb")}),
            tab("Miami Art Week!", {"3": pane(str(home / "gone"), None, "cccc")}),
            tab("Not Mirrored", {"4": pane("/", "lost", "dddd")}),
            tab("Clash", {"5": pane("/", "live-one", "eeee")}),
            tab("Shell only", {"6": {"cwd": "/", "agent_name": None, "managed_agent_kind": None, "agent_session": None}}),
            tab("Split", {"7": pane("/", "left", "ffff"), "8": {"cwd": "/", "agent_session": None}}),
        ]}],
    }))

    out = run(home, log, session_file, projects)
    calls = log.read_text().splitlines()
    expected = [
        "workspace list",
        "agent list",
        f"tab create --workspace w1 --cwd {repo_dir} --label Bookmark Sync --no-focus",
        "agent start bookmark-sync --kind claude --pane w1:p3 -- --resume bbbb",
        f"tab create --workspace w1 --cwd {home} --label Miami Art Week! --no-focus",
        "agent start miami-art-week --kind claude --pane w1:p5 -- --resume cccc",
        "tab create --workspace w1 --cwd / --label Clash --no-focus",
        "agent start live-one-2 --kind claude --pane w1:p7 -- --resume eeee",
        "tab create --workspace w1 --cwd / --label Split --no-focus",
        "agent start left --kind claude --pane w1:p9 -- --resume ffff",
    ]
    assert calls == expected, "\n".join(["herdr calls differ:", *calls, "--- expected:", *expected])
    assert "aaaa" in out and "already live" in out, out
    assert "dddd" in out and "not mirrored" in out, out

    out = run(home, log, session_file, projects, "--dry-run")
    calls = log.read_text().splitlines()
    assert calls == ["workspace list", "agent list"], calls
    assert "bookmark-sync" in out and "live-one-2" in out, out

    missing = subprocess.run(
        [sys.executable, str(script), "--session-file", str(home / "nope.json"), "--projects", str(projects)],
        capture_output=True, text=True,
    )
    assert missing.returncode == 1 and "no mirrored session.json" in missing.stderr, missing

print("herdr-takeover: all checks passed")
