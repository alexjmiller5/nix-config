#!/usr/bin/env bash
# Each host links exactly its own capability sheet and exports AGENT_MACHINE.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1"; exit 1; }
for pair in macbook-air:macbook mac-mini:mini; do
  host=${pair%%:*}; profile=${pair##*:}
  # mkOutOfStoreSymlink names its store path after the target's basename, so
  # the source path proves which sheet is linked without building anything.
  got=$(nix eval --raw ".#darwinConfigurations.$host.config.home-manager.users" \
    --apply "users: let u = builtins.head (builtins.attrValues users); in
      u.agentMachine.profile + \" \" + u.home.sessionVariables.AGENT_MACHINE + \" \"
      + u.agentMachine.sheetsDir + \" \" + toString u.xdg.configFile.\"agent-machine/AGENTS.md\".source")
  read -r prof var dir link <<<"$got"
  [ "$prof" = "$profile" ] || fail "$host profile is $prof"
  [ "$var" = "$profile" ] || fail "$host AGENT_MACHINE is $var"
  case "$dir" in */.config/agent-config/machines) ;; *) fail "$host sheetsDir is $dir";; esac
  case "$link" in *$profile.md) ;; *) fail "$host links $link";; esac
  # Herdr panes and ssh commands are non-login shells: the variable must come
  # from .zshenv (programs.zsh.envExtra), not only from login-time session vars.
  envextra=$(nix eval --raw ".#darwinConfigurations.$host.config.home-manager.users" \
    --apply "users: (builtins.head (builtins.attrValues users)).programs.zsh.envExtra")
  case "$envextra" in *"export AGENT_MACHINE=$profile"*) ;; *) fail "$host .zshenv lacks AGENT_MACHINE";; esac
done
echo "agent-machine: all checks passed"
