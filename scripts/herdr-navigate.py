"""Navigate every open Herdr tab in machine/space/tab order, across layouts."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys


def destination(snapshot, step):
    tabs, current = [], None
    for space in snapshot["spaces"]:
        for tab in space["tabs"]:
            if tab.get("settled"):
                continue
            identifier = tab["id"]
            if not isinstance(identifier, str) or not identifier or identifier in tabs:
                raise ValueError("Invalid tab identity")
            if space.get("active") and tab.get("active"):
                if current is not None:
                    raise ValueError("Ambiguous current tab")
                current = len(tabs)
            tabs.append(identifier)
    if not tabs:
        return None
    if current is None:
        return tabs[0 if step > 0 else -1]
    return tabs[(current + step) % len(tabs)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("direction", choices=["next", "previous"])
    parser.add_argument("--herdr-app", default="herdr-app")
    args = parser.parse_args()
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "herdr-navigate"
    try:
        state.mkdir(parents=True, exist_ok=True)
        # Serialise rapid presses so each one starts from the last selection.
        with (state / "lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            response = subprocess.run([args.herdr_app, "ls"], check=True, capture_output=True, text=True, timeout=5)
            target = destination(json.loads(response.stdout), 1 if args.direction == "next" else -1)
            if target:
                subprocess.run([args.herdr_app, "do", "tab.select", "--id", target], check=True, capture_output=True, text=True, timeout=5)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        print("Herdr session navigation unavailable; check the app connection.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
