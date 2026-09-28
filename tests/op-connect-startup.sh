#!/usr/bin/env bash
# Exercise the actual declared launch environment, not the login shell.
set -euo pipefail
cd "$(dirname "$0")/.."
# colima shells out to macOS ssh and the Lima tooling from the launchd PATH.
docker_path=$(nix eval --raw .#darwinConfigurations.macbook-air.config.home-manager.users \
  --apply 'users: (builtins.head (builtins.attrValues users)).launchd.agents.op-connect.config.EnvironmentVariables.PATH')
env -i PATH="$docker_path" /bin/sh -c 'command -v colima >/dev/null && command -v docker >/dev/null && command -v docker-compose >/dev/null && command -v ssh >/dev/null'
echo 'op-connect-startup: colima, docker, docker-compose and ssh are on the service PATH'
# A Docker Desktop leftover (~/.docker/config.json credsStore=desktop) must not
# reach Compose: the service runs with its own writable Docker config directory
# (start_runtime creates it; a store symlink there breaks colima's provisioning).
docker_config=$(nix eval --raw .#darwinConfigurations.macbook-air.config.home-manager.users \
  --apply 'users: (builtins.head (builtins.attrValues users)).launchd.agents.op-connect.config.EnvironmentVariables.DOCKER_CONFIG')
case "$docker_config" in */1password-connect/docker) ;; *) echo "FAIL: DOCKER_CONFIG is '$docker_config'"; exit 1;; esac
echo 'op-connect-startup: Compose runs with a private Docker config'
