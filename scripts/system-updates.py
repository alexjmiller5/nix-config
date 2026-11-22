"""Build, record and activate weekly flake updates from an isolated clone."""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import subprocess
import tempfile
import time


def run(args, cwd=None, capture=False):
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None, timeout=7200)


def update(repo, host, state, force=False):
    state.mkdir(parents=True, exist_ok=True)
    success = state / 'last-success'
    if not force and success.exists() and time.time() - success.stat().st_mtime < 7 * 86400:
        print('Last successful system update was less than a week ago.', flush=True)
        return
    os.environ['AGENT_SHELL'] = 'repo-sync'
    origin = run(['git', 'remote', 'get-url', 'origin'], repo, True).stdout.strip()
    with tempfile.TemporaryDirectory(prefix='system-updates-') as tmp:
        run(['git', 'clone', '--depth', '1', '--branch', 'main', origin, tmp])
        run(['nix', 'flake', 'update'], tmp)
        run(['nix', 'flake', 'check'], tmp)
        run(['nix', 'build', f'.#darwinConfigurations.{host}.system', '--no-link', '--max-jobs', '1', '--cores', '2'], tmp)
        changed = run(['git', 'status', '--porcelain', '--', 'flake.lock'], tmp, True).stdout
        if changed:
            run(['git', 'add', 'flake.lock'], tmp)
            # Use the configured repository identity; never embed a person's identity.
            for key in ('user.name', 'user.email'):
                value = run(['git', 'config', '--get', key], repo, True).stdout.strip()
                run(['git', 'config', key, value], tmp)
            run(['git', '-c', 'commit.gpgsign=false', 'commit', '-m', 'Update flake inputs'], tmp)
            # A concurrent update refuses the push. Never overwrite or deploy an unrecorded update.
            run(['git', 'push', 'origin', 'HEAD:main'], tmp)
        run(['sudo', '-n', '/run/current-system/sw/bin/darwin-rebuild', 'switch', '--flake', f'{tmp}#{host}'], tmp)
    success.write_text(datetime.now(timezone.utc).isoformat() + '\n')
    # Advance a clean checkout only; preserve all work in progress.
    if not run(['git', 'status', '--porcelain'], repo, True).stdout:
        run(['git', 'pull', '--ff-only'], repo)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--host', required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    try:
        update(args.repo, args.host, args.state, args.force)
    except Exception as exc:
        print(f'System update FAILED: {exc}', flush=True)
        subprocess.run(['/usr/bin/osascript', '-e', 'display notification "Automatic system update failed. See system-updates.log." with title "System updates"'], check=False)
        raise
