"""Remove scratch that macOS tools leave behind for good (home/scratch-sweeper.nix).

- Chrome bundle clones: Chrome clones its app bundle into
  <DARWIN_USER_TEMP_DIR>/../X/com.google.Chrome.code_sign_clone/ at every
  launch and removes the clone only on a clean exit, so every killed Chrome
  leaves one behind. Taken once older than a day and no process (lsof +D)
  holds a file in it open.
- Xcode DerivedData entries in which nothing changed for --derived-data-days.

Each removal and the free space before and after go to stdout (the launchd
log); --dry-run only lists what it would remove.
"""

import argparse
import os
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path

DAY = 86400


def stale(path, cutoff):
    """True when nothing under path (symlinks not followed) changed after cutoff."""
    if path.lstat().st_mtime > cutoff:
        return False
    for dirpath, dirnames, filenames in os.walk(path):
        for name in dirnames + filenames:
            try:
                if os.lstat(os.path.join(dirpath, name)).st_mtime > cutoff:
                    return False
            except FileNotFoundError:
                pass
    return True


def in_use(path):
    r = subprocess.run(["lsof", "+D", str(path)], capture_output=True, text=True)
    # lsof exits 1 both for "nothing open" and for errors; only output is proof.
    return bool(r.stdout.strip()) or r.returncode > 1


def entries(root, pattern="*"):
    if not root.is_dir():
        return []
    return sorted(p for p in root.glob(pattern) if p.is_dir() and not p.is_symlink())


def candidates(home, now, derived_data_days):
    temp = subprocess.run(["getconf", "DARWIN_USER_TEMP_DIR"], capture_output=True, text=True, check=True)
    clones = Path(temp.stdout.strip()).parent / "X/com.google.Chrome.code_sign_clone"
    for p in entries(clones, "code_sign_clone.*"):
        if stale(p, now - DAY) and not in_use(p):
            yield p
    for p in entries(home / "Library/Developer/Xcode/DerivedData"):
        if stale(p, now - derived_data_days * DAY):
            yield p


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--derived-data-days", type=int, default=14)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    home = Path.home()

    def free():
        return f"free {shutil.disk_usage(home).free / 2**30:.1f} GiB"

    print(f"{datetime.now():%Y-%m-%d %H:%M:%S} {free()}{' (dry run)' if args.dry_run else ''}", flush=True)
    for p in candidates(home, time.time(), args.derived_data_days):
        if args.dry_run:
            print(f"would remove {p}")
            continue
        try:
            shutil.rmtree(p)
            print(f"removed {p}", flush=True)
        except OSError as e:
            print(f"failed {p}: {e}", flush=True)
    print(free())


if __name__ == "__main__":
    main()
