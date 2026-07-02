#!/usr/bin/env bash
# Bootstrap a fresh Mac: install Determinate Nix, then let the flake do
# everything else (packages, Homebrew itself via nix-homebrew, casks,
# system settings, dotfiles, authorized_keys).
# Idempotent; rerun safely if it dies partway.
#
# Run ON the target machine (needs a tty for sudo prompts):
#   bash <(curl -fsSL https://raw.githubusercontent.com/alexjmiller5/nix-config/main/scripts/bootstrap.sh)
set -euo pipefail

FLAKE="github:alexjmiller5/nix-config#mac-mini"

if [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  echo "==> Installing Determinate Nix"
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
fi

echo "==> Applying nix-darwin config: $FLAKE"
sudo /nix/var/nix/profiles/default/bin/nix run nix-darwin/master#darwin-rebuild -- switch --flake "$FLAKE"

echo "==> Done. Day-to-day: 'just switch' from a clone, or 'just switch-remote'."
