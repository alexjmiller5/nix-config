# Deploy the mac-mini config from THIS laptop — no clone on the Mini.
# Copies this flake + its inputs into the Mini's nix store (via ssh://, so it uses
# your ~/.ssh/config + 1Password agent), then runs the Mini's OWN darwin-rebuild for
# a correct activation (passwordless via the NOPASSWD rule in darwin-base.nix). Deploys COMMITTED
# state (commit + push first if you want the change on GitHub too).
deploy host="mac-mini-tailscale":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "→ copying flake + inputs to {{host}} …"
    flake="$(nix flake archive --to "ssh://{{host}}" --json \
      | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])')"
    echo "→ activating on {{host}} …"
    ssh -t "{{host}}" "sudo /run/current-system/sw/bin/darwin-rebuild switch --flake '$flake#mac-mini'"

# Apply locally — only if you're actually ON the Mini with a checkout (you shouldn't need this).
switch:
    sudo darwin-rebuild switch --flake .#mac-mini

# Apply the laptop's config ON the laptop. Works before nix-darwin is installed:
# builds the system first, then uses the build's own darwin-rebuild to activate.
switch-laptop:
    #!/usr/bin/env bash
    set -euo pipefail
    nix build .#darwinConfigurations.macbook-air.system
    # /run/current-system path matches the NOPASSWD sudoers rule (darwin-base.nix);
    # the ./result fallback is bootstrap-only (first activation, password prompt).
    dr=/run/current-system/sw/bin/darwin-rebuild
    [ -x "$dr" ] || dr=./result/sw/bin/darwin-rebuild
    sudo "$dr" switch --flake .#macbook-air

# Validate the flake
check:
    nix flake check
    python3 tests/finder-defaults.py
    bash tests/agent-detect.sh
    bash tests/op-auth-guard.sh
    python3 tests/machine-vault-git.py
    python3 tests/op-auth.py
    python3 tests/op-connect.py
    bash tests/op-connect-startup.sh
    bash tests/posthog-auth.sh
    bash tests/claude-memory.sh
    bash tests/wait-for-remote.sh

# Bump all inputs
update:
    nix flake update

# Format all nix files (RFC 166 style via the flake's formatter)
fmt:
    nix fmt .
