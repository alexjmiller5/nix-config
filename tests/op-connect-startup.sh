#!/usr/bin/env bash
# Docker's privileged-helper installer invokes macOS tools from its inherited
# PATH. Exercise the actual declared launch environment, not the login shell.
set -euo pipefail
cd "$(dirname "$0")/.."
docker_path=$(nix eval --raw .#darwinConfigurations.macbook-air.config.home-manager.users \
  --apply 'users: (builtins.head (builtins.attrValues users)).launchd.agents.op-connect.config.EnvironmentVariables.PATH')
env -i PATH="$docker_path" /bin/sh -c 'command -v md5 >/dev/null && command -v base64 >/dev/null'
echo 'op-connect-startup: Docker can find its macOS installation helpers'
