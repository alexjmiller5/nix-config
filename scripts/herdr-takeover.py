#!/usr/bin/env python3
"""Recreate another machine's Herdr Claude tabs here, resuming each session.

Reads a mirrored Herdr session.json, and for every pane that held a Claude
session whose transcript is mirrored under ~/.claude/projects, creates a tab in
this machine's Herdr (same label, same cwd when it exists here) and starts
`claude --resume <id>` in it. Sessions already live here are skipped, so the
command is safe to rerun.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def herdr(*args):
    out = subprocess.run(["herdr", *args], check=True, capture_output=True, text=True).stdout
    return json.loads(out)["result"]


def slug(label):
    name = re.sub(r"[^a-z0-9]+", "-", label.lower()).strip("-")[:32]
    return name if re.match(r"[a-z]", name) else f"t-{name}"[:32]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--session-file", required=True, help="mirrored Herdr session.json")
    parser.add_argument("--projects", default=Path.home() / ".claude/projects", type=Path)
    parser.add_argument("--dry-run", action="store_true", help="print the plan, create nothing")
    args = parser.parse_args()

    if not Path(args.session_file).is_file():
        sys.exit(f"no mirrored session.json at {args.session_file} (has herdr-takeover-sync run yet?)")
    session = json.loads(Path(args.session_file).read_text())
    workspaces = herdr("workspace", "list")["workspaces"]
    workspace = next((w for w in workspaces if w.get("focused")), workspaces[0])["workspace_id"]
    live = herdr("agent", "list")["agents"]
    live_ids = {(a.get("agent_session") or {}).get("value") for a in live}
    names = {a.get("name") for a in live if a.get("name")}

    for ws in session["workspaces"]:
        for tab in ws["tabs"]:
            label = tab.get("custom_name") or ""
            for pane in tab["panes"].values():
                agent = pane.get("agent_session") or {}
                sid = agent.get("value")
                if agent.get("agent") != "claude" or not sid:
                    continue
                if sid in live_ids:
                    print(f"skip {label!r} {sid}: already live here")
                    continue
                if not list(args.projects.glob(f"*/{sid}.jsonl")):
                    print(f"skip {label!r} {sid}: transcript not mirrored")
                    continue
                name = base = pane.get("agent_name") or slug(label or "takeover")
                for n in range(2, 100):
                    if name not in names:
                        break
                    name = f"{base[:29]}-{n}"
                names.add(name)
                cwd = pane.get("cwd") or ""
                if not os.path.isdir(cwd):
                    cwd = str(Path.home())
                print(f"{'plan' if args.dry_run else 'resume'} {label!r} as {name} in {cwd}: {sid}")
                if args.dry_run:
                    continue
                create = ["tab", "create", "--workspace", workspace, "--cwd", cwd]
                if label:
                    create += ["--label", label]
                pane_id = herdr(*create, "--no-focus")["root_pane"]["pane_id"]
                herdr("agent", "start", name, "--kind", "claude", "--pane", pane_id, "--", "--resume", sid)


if __name__ == "__main__":
    sys.exit(main())
