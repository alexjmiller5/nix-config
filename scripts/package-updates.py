"""Upgrade Homebrew packages and restart only services whose binaries changed."""
import json
import os
from pathlib import Path
import subprocess
import sys


def run(args):
    subprocess.run(args, check=True, timeout=3600)


def services(brew):
    rows = json.loads(subprocess.check_output([brew, 'services', 'list', '--json'], timeout=30))
    return {r['name']: os.path.realpath(Path(brew).parent.parent / 'opt' / r['name'])
            for r in rows if r['status'] == 'started'}


def update(brew):
    before = services(brew)
    run([brew, 'update'])
    try:
        run([brew, 'upgrade', '--formula', '--cask'])
    finally:
        after = services(brew)
        for name, version in before.items():
            if name in after and after[name] != version:
                run([brew, 'services', 'restart', name])


if __name__ == '__main__':
    try:
        update(sys.argv[1])
    except Exception:
        subprocess.run(['/usr/bin/osascript', '-e', 'display notification "Automatic package update failed. See package-updates.log." with title "Package updates"'], check=False)
        raise
