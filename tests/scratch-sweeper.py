"""Fixture test for home/scratch-sweeper.py.

A fake HOME holds DerivedData entries and a fake DARWIN_USER_TEMP_DIR (via a
stub `getconf`) holds Chrome bundle clones; a stub `lsof` reports the
"inuse" clone as open. Asserts which entries a run removes, that --dry-run
removes nothing, and that nothing outside the two roots is touched.

Run: python3 tests/scratch-sweeper.py
"""

import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
script = repo / "home/scratch-sweeper.py"
DAY = 86400


def make(path, age_days):
    """A dir holding one file, everything aged `age_days`."""
    path.mkdir(parents=True)
    (path / "f").write_text("x")
    t = time.time() - age_days * DAY
    for p in (path / "f", path):
        os.utime(p, (t, t))


def run(tmp, *args):
    env = {**os.environ, "HOME": str(tmp / "home"), "PATH": f"{tmp / 'bin'}:{os.environ['PATH']}"}
    r = subprocess.run([sys.executable, str(script), *args], env=env, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return r.stdout


with tempfile.TemporaryDirectory() as d:
    tmp = Path(d)
    (tmp / "bin").mkdir()
    for name, body in {
        "getconf": f'echo "{tmp}/folders/T/"',
        "lsof": 'case "$2" in *inuse*) echo "Google 1 me txt REG $2/x";; *) exit 1;; esac',
    }.items():
        (tmp / "bin" / name).write_text(f"#!/bin/sh\n{body}\n")
        (tmp / "bin" / name).chmod(0o755)

    clones = tmp / "folders/X/com.google.Chrome.code_sign_clone"
    make(clones / "code_sign_clone.old", 2)
    make(clones / "code_sign_clone.inuse", 2)
    make(clones / "code_sign_clone.fresh", 0.1)
    make(tmp / "folders/X/other", 30)

    dd = tmp / "home/Library/Developer/Xcode/DerivedData"
    make(dd / "Old-abc", 20)
    make(dd / "Active-xyz", 20)
    make(dd / "Active-xyz/Build/Intermediates.noindex", 1)  # one recent file deep inside
    os.utime(dd / "Active-xyz", (time.time() - 20 * DAY,) * 2)
    make(dd / "ModuleCache.noindex", 3)
    make(tmp / "elsewhere", 30)
    (dd / "link").symlink_to(tmp / "elsewhere")
    os.utime(dd / "link", (time.time() - 30 * DAY,) * 2, follow_symlinks=False)

    removed = [clones / "code_sign_clone.old", dd / "Old-abc"]
    kept = [
        clones / "code_sign_clone.inuse",
        clones / "code_sign_clone.fresh",
        tmp / "folders/X/other",
        dd / "Active-xyz",
        dd / "ModuleCache.noindex",
        dd / "link",
        tmp / "elsewhere/f",
    ]

    out = run(tmp, "--dry-run")
    assert all(p.exists() for p in removed + kept), "dry run deleted something"
    for p in removed:
        assert f"would remove {p}" in out, out
    assert out.count("would remove") == len(removed), out

    out = run(tmp, "--derived-data-days", "14")
    assert not any(p.exists() for p in removed), out
    assert all(p.exists() for p in kept), out
    for p in removed:
        assert f"removed {p}" in out, out
    assert out.count("free ") == 2, out

    # A shorter window also takes the 3-day-old ModuleCache.
    out = run(tmp, "--derived-data-days", "2")
    assert not (dd / "ModuleCache.noindex").exists(), out
    assert (dd / "Active-xyz").exists(), out

print("scratch-sweeper: ok")
