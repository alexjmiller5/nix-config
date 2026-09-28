#!/usr/bin/env bash
# The activation seed for ~/.claude.json: home-dir trust plus the built-in
# computer-use MCP enabled for the home project, merged into whatever Claude
# already persisted, idempotent, and never touching other keys.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1"; exit 1; }
script=$(nix eval --raw .#darwinConfigurations.mac-mini.config.home-manager.users \
  --apply 'users: (builtins.head (builtins.attrValues users)).home.activation.claudeTrustHomeDir.data')
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
printf '{"projects":{"%s":{"enabledMcpServers":["other"],"allowedTools":["x"]}},"keep":1}' "$scratch" > "$scratch/.claude.json"
for _ in 1 2; do HOME="$scratch" bash -c "$script"; done
got=$(jq -c --arg d "$scratch" '[.projects[$d].hasTrustDialogAccepted, .projects[$d].enabledMcpServers, .projects[$d].allowedTools, .keep]' "$scratch/.claude.json")
[ "$got" = '[true,["other","computer-use"],["x"],1]' ] || fail "seed produced $got"
rm "$scratch/.claude.json"
HOME="$scratch" bash -c "$script"
got=$(jq -c --arg d "$scratch" '[.projects[$d].hasTrustDialogAccepted, .projects[$d].enabledMcpServers]' "$scratch/.claude.json")
[ "$got" = '[true,["computer-use"]]' ] || fail "fresh seed produced $got"
echo "claude-json-seed: all checks passed"
