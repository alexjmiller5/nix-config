# nix-config

Declarative macOS machine configs via [nix-darwin](https://github.com/nix-darwin/nix-darwin) + [home-manager](https://github.com/nix-community/home-manager).

| Host          | Config                                                                                | Status                      |
| ------------- | ------------------------------------------------------------------------------------- | --------------------------- |
| `mac-mini`    | `hosts/mac-mini.nix` (system) + `home/mac-mini.nix` (user)                            | active                      |
| `macbook-air` | `hosts/macbook-air.nix` + `home/macbook-air.nix` (full shell/dotfiles/agents profile) | **active since 2026-07-28** |

Day-to-day: edit config, then `just switch-laptop` (on the laptop), `just deploy` (mini, from the laptop), or `just switch` (on the mini). `just check` validates the flake.

The flake also exports `homeModules.*` (zsh, git, alias categories) for
consumption by other flakes — e.g. a work-machine config pinning this repo.

## Manual setup steps (per host)

Everything nix *cannot* do, per machine — TCC grants, first-boot quirks,
one-time app setup, bootstrap order:

* **MacBook Air**: [MANUAL-macbook-air.md](MANUAL-macbook-air.md)
* **Mac mini (headless, from scratch)**: [MANUAL-mac-mini.md](MANUAL-mac-mini.md)

