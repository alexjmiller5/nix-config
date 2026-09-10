# nix-config

Declarative macOS machine configs via [nix-darwin](https://github.com/nix-darwin/nix-darwin) + [home-manager](https://github.com/nix-community/home-manager).

| Host          | Config                                                                                | Status                      |
| ------------- | ------------------------------------------------------------------------------------- | --------------------------- |
| `mac-mini`    | `hosts/mac-mini.nix` (system) + `home/mac-mini.nix` (user)                            | active                      |
| `macbook-air` | `hosts/macbook-air.nix` + `home/macbook-air.nix` (full shell/dotfiles/agents profile) | **active since 2026-07-28** |

Day-to-day: edit config, then `just switch-laptop` (on the laptop), `just deploy` (mini, from the laptop), or `just switch` (on the mini). `just check` validates the flake.

The flake also exports `homeModules.*` (zsh, git, alias categories) for
consumption by other flakes — e.g. a work-machine config pinning this repo.

## Herdr in Ghostty

Run `herdr-window` from a project directory to open a dedicated Ghostty
window. That window uses a native Ghostty key table to control Herdr:

| Shortcut | Action |
| --- | --- |
| Cmd+T | New tab |
| Cmd+Shift+[ / ] | Previous / next tab |
| Cmd+1 through 9 | Jump to tab |
| Cmd+W | Close tab |
| Cmd+D / Cmd+Shift+D | Split right / down |
| Cmd+[ / ] | Previous / next pane |
| Cmd+Shift+Enter | Toggle pane zoom |
| Cmd+Shift+N | New workspace |
| Cmd+P | Workspace and tab picker |
| Cmd+Option+[ / ] | Previous / next agent |
| Cmd+Backslash | Toggle sidebar |
| Cmd+Shift+W | Detach, leaving processes running |
| Cmd+, | Settings |

Ordinary Ghostty windows keep their existing shortcuts. Running plain
`herdr` attaches with Herdr's Ctrl+B prefix shortcuts instead. Preferences
are managed in `home/herdr.nix`; edit that module rather than saving changes
in Herdr's settings screen. Closing a client preserves running processes;
a machine restart restores saved layout, but agent conversation restoration
also requires the corresponding Herdr integration.

## Manual setup steps (per host)

Everything nix *cannot* do, per machine — TCC grants, first-boot quirks,
one-time app setup, bootstrap order:

* **MacBook Air**: [MANUAL-macbook-air.md](MANUAL-macbook-air.md)
* **Mac mini (headless, from scratch)**: [MANUAL-mac-mini.md](MANUAL-mac-mini.md)
