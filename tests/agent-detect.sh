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
trap 'rm -f "$scratch/.zshenv" "$scratch/.local/state/op/agent-sa-token"; rmdir "$scratch/.local/state/op" "$scratch/.local/state" "$scratch/.local" "$scratch"' EXIT
mkdir -p "$scratch/.local/state/op"
printf fixture-token > "$scratch/.local/state/op/agent-sa-token"
nix eval --raw .#darwinConfigurations.macbook-air.config.home-manager.users \
  --apply 'users: (builtins.head (builtins.attrValues users)).programs.zsh.envExtra' \
  > "$scratch/.zshenv"
for mode in codex claude human thread; do
  detected=$(
    env -i PATH="$PATH" HOME="$scratch" ZDOTDIR="$scratch" \
      CODEX_SESSION_ID="$([ "$mode" != codex ] || echo test-session)" \
      CODEX_THREAD_ID="$([ "$mode" != thread ] || echo test-thread)" \
      CLAUDECODE="$([ "$mode" != claude ] || echo 1)" \
      zsh -c 'printf "%s:%s" "${AGENT_SHELL:-human}" "${OP_SERVICE_ACCOUNT_TOKEN:-}"'
  )
  expected="$mode:fixture-token"
  [ "$mode" != human ] || expected=human:
  [ "$mode" != thread ] || expected=codex:fixture-token
  [ "$detected" = "$expected" ] || fail "noninteractive $mode shell: $detected, expected $expected"
done

for token in caller-token ''; do
  detected=$(env -i PATH="$PATH" HOME="$scratch" ZDOTDIR="$scratch" \
    CODEX_SESSION_ID=test-session OP_SERVICE_ACCOUNT_TOKEN="$token" \
    zsh -c 'printf "%s" "$OP_SERVICE_ACCOUNT_TOKEN"')
  [ "$detected" = "${token:-fixture-token}" ] || fail "caller token was overwritten"
done
detected=$(env -i PATH="$PATH" HOME="$scratch" ZDOTDIR="$scratch" \
  CODEX_SESSION_ID=test-session OP_SERVICE_ACCOUNT_TOKEN=caller-token AGENT_OP_AUTH=desktop \
  zsh -c 'zsh -c '\''printf "%s:%s" "$AGENT_SHELL" "${OP_SERVICE_ACCOUNT_TOKEN:-}"'\''')
[ "$detected" = codex: ] || fail "desktop override did not survive nested shells: $detected"

echo "agent-detect: all checks passed"
