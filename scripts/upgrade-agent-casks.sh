#!/usr/bin/env bash
set -uo pipefail
brew=${1:-/opt/homebrew/bin/brew}
status=0
"$brew" upgrade claude-code@latest codex || status=$?
# These declared CLI casks must launch from unattended SSH/core terminals.
# Also strip after a partial upgrade, which may already have linked a new binary.
for cask in claude-code@latest codex; do
  root=$("$brew" --caskroom "$cask") || continue
  if [ -d "$root" ]; then
    xattr -dr com.apple.quarantine "$root" || status=1
  fi
done
exit "$status"
