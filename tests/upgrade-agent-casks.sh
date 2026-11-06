#!/usr/bin/env bash
set -euo pipefail
scratch=$(mktemp -d)
trap 'find "$scratch" -depth -delete' EXIT
mkdir -p "$scratch/bin" "$scratch/casks/codex" "$scratch/casks/claude-code@latest"
export TEST_ROOT="$scratch"
cat > "$scratch/bin/brew" <<'SH'
#!/usr/bin/env bash
if [ "$1" = upgrade ]; then exit "${BREW_STATUS:-0}"; fi
printf '%s/casks/%s\n' "$TEST_ROOT" "$2"
SH
cat > "$scratch/bin/xattr" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_ROOT/stripped"
SH
chmod +x "$scratch/bin/"*
export PATH="$scratch/bin:$PATH"
bash scripts/upgrade-agent-casks.sh "$scratch/bin/brew"
rg -q -- '-dr com.apple.quarantine .*/casks/codex' "$scratch/stripped"
rg -q -- '-dr com.apple.quarantine .*/casks/claude-code@latest' "$scratch/stripped"
set +e
BREW_STATUS=7 bash scripts/upgrade-agent-casks.sh "$scratch/bin/brew"
result=$?
set -e
[ "$result" = 7 ]
[ "$(wc -l < "$scratch/stripped" | tr -d ' ')" = 4 ]
echo 'Agent upgrades strip both casks even after partial failure, preserving exit status'
