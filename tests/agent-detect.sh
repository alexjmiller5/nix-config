#!/usr/bin/env bash
# Behavioral test for the shared agent-shell detection seam.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }

detected=$(
  env -i PATH="$PATH" CODEX_SESSION_ID=test-session \
    sh -c '. ./home/agent-detect.sh; printf "%s" "${AGENT_SHELL:-}"'
)
[ "$detected" = codex ] || fail "Codex session did not select the agent credential seam"

# Exercise the actual noninteractive zsh startup configuration, not just
# detection in isolation. An interactive-only hook leaves SSH on desktop auth.
scratch=$(mktemp -d)
trap 'rm -f "$scratch/.zshenv"; rmdir "$scratch"' EXIT
nix eval --raw .#darwinConfigurations.macbook-air.config.home-manager.users \
  --apply 'users: (builtins.head (builtins.attrValues users)).programs.zsh.envExtra' \
  > "$scratch/.zshenv"
for mode in codex claude human; do
  detected=$(
    env -i PATH="$PATH" HOME="$scratch" ZDOTDIR="$scratch" \
      CODEX_SESSION_ID="$([ "$mode" != codex ] || echo test-session)" \
      CLAUDECODE="$([ "$mode" != claude ] || echo 1)" \
      zsh -c 'printf "%s" "${AGENT_SHELL:-human}"'
  )
  [ "$detected" = "$mode" ] || fail "noninteractive $mode shell detected as $detected"
done

echo "agent-detect: all checks passed"
