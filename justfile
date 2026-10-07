# Deploy a host's config to it from the OTHER machine (the switch-* aliases
# pick this or a local switch by where they run). Copies this flake + its inputs
# into the target's nix store (via ssh://, so it uses ~/.ssh/config), then runs
# the target's OWN darwin-rebuild (passwordless via the NOPASSWD rule in
# darwin-base.nix). Deploys the working tree, not GitHub: commit + push too.
deploy host="mac-mini-tailscale" attr="mac-mini":
    #!/usr/bin/env bash
    set -euo pipefail
    just manual
    echo "→ copying flake + inputs to {{host}} …"
    flake="$(nix flake archive --to "ssh://{{host}}" --json \
      | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])')"
    echo "→ activating on {{host}} …"
    ssh -t "{{host}}" "sudo /run/current-system/sw/bin/darwin-rebuild switch --flake '$flake#{{attr}}'"

# Apply the mini's config ON the mini (the switch-mini alias there).
switch:
    just manual
    sudo darwin-rebuild switch --flake .#mac-mini

# Apply the laptop's config ON the laptop. Works before nix-darwin is installed:
# builds the system first, then uses the build's own darwin-rebuild to activate.
switch-laptop:
    #!/usr/bin/env bash
    set -euo pipefail
    just manual
    nix build .#darwinConfigurations.macbook-air.system
    # /run/current-system path matches the NOPASSWD sudoers rule (darwin-base.nix);
    # the ./result fallback is bootstrap-only (first activation, password prompt).
    dr=/run/current-system/sw/bin/darwin-rebuild
    [ -x "$dr" ] || dr=./result/sw/bin/darwin-rebuild
    sudo "$dr" switch --flake .#macbook-air

# Validate the flake
check:
    nix flake check
    python3 tests/manual-render.py
    /usr/bin/ruby tests/flighty-install.rb
    python3 tests/finder-defaults.py
    bash tests/agent-detect.sh
    bash tests/agent-machine.sh
    bash tests/claude-json-seed.sh
    bash tests/op-auth-guard.sh
    bash tests/git-hooks.sh
    python3 tests/machine-vault-git.py
    python3 tests/op-auth.py
    python3 tests/op-connect.py
    bash tests/op-connect-startup.sh
    bash tests/posthog-auth.sh
    bash tests/claude-memory.sh
    bash tests/wait-for-remote.sh
    python3 tests/herdr-takeover.py
    bash tests/wifi-watchdog.sh

# Render MANUAL-<host>.md from the declared manual.steps; rewrites only when the body changed
manual:
    #!/usr/bin/env bash
    set -euo pipefail
    for h in macbook-air mac-mini; do
      fresh="$(nix build --no-link --print-out-paths ".#manual-$h")"
      if [ -f "MANUAL-$h.md" ] && cmp -s <(tail -n +2 "$fresh") <(tail -n +2 "MANUAL-$h.md"); then
        echo "MANUAL-$h.md unchanged"
      else
        cp "$fresh" "MANUAL-$h.md" && chmod 644 "MANUAL-$h.md" && echo "MANUAL-$h.md rendered"
      fi
    done

# Re-capture a snapshot (tcc | chrome-ui) into snapshots/<host>/; remote hosts run over ssh
snapshot name host="macbook-air":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "snapshots/{{host}}"
    if [ "{{host}}" = macbook-air ]; then
      capture-snapshot "{{name}}" > "snapshots/{{host}}/{{name}}.txt"
    else
      ssh "{{host}}-tailscale" capture-snapshot "{{name}}" > "snapshots/{{host}}/{{name}}.txt"
    fi
    git diff --stat -- "snapshots/{{host}}/{{name}}.txt"

# Bump all inputs
update:
    nix flake update

# Format all nix files (RFC 166 style via the flake's formatter)
fmt:
    nix fmt .
