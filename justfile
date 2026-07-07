# Deploy the mac-mini config from THIS laptop — no clone on the Mini.
# Copies this flake + its inputs into the Mini's nix store (via ssh://, so it uses
# your ~/.ssh/config + 1Password agent), then runs the Mini's OWN darwin-rebuild for
# a correct activation. Prompts once for the Mini's sudo password. Deploys COMMITTED
# state (commit + push first if you want the change on GitHub too).
deploy host="mac-mini-tailscale":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "→ copying flake + inputs to {{host}} …"
    flake="$(nix flake archive --to "ssh://{{host}}" --json \
      | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])')"
    echo "→ activating on {{host}} — enter the Mini's sudo password when prompted:"
    ssh -t "{{host}}" "sudo /run/current-system/sw/bin/darwin-rebuild switch --flake '$flake#mac-mini'"

# Apply locally — only if you're actually ON the Mini with a checkout (you shouldn't need this).
switch:
    sudo darwin-rebuild switch --flake .#mac-mini

# Validate the flake
check:
    nix flake check

# Bump all inputs
update:
    nix flake update
