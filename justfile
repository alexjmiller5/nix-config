# Apply the config on the mini (run from a clone of this repo)
switch:
    sudo darwin-rebuild switch --flake .#mac-mini

# Apply straight from GitHub without a local clone
switch-remote:
    sudo darwin-rebuild switch --flake github:alexjmiller5/nix-config#mac-mini

# Validate the flake
check:
    nix flake check

# Bump all inputs
update:
    nix flake update
