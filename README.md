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

Run `hdr` (an alias for `herdr-window`) from a project directory to open a dedicated Ghostty
window. Hammerspoon (`herdrHotkeys.lua`) gives that window macOS-style shortcuts,
typing Herdr's ctrl+b prefix for each one:

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

Ordinary Ghostty windows keep their native shortcuts: the hotkeys are enabled
only while a window `herdr-window` opened is focused (it claims the window
through a sentinel file that Hammerspoon consumes). A Ghostty key table would
also work, but an active one paints an indicator pill Ghostty cannot hide. To
adopt a herdr window opened before this - or any other way - focus it and run
`hs -c 'require("herdrHotkeys").markFocusedWindow()'`. The prefix keys the
hotkeys type are pinned in `home/herdr.nix`, so a changed Herdr default cannot
silently move a shortcut. Bare `herdr` is a shell function that runs
`herdr-window` too, so the shortcuts are never missed by forgetting the alias;
`herdr <subcommand>` still hits the real binary, as does any host without
Ghostty. Preferences
are managed in `home/herdr.nix`; edit that module rather than saving changes
in Herdr's settings screen. Closing a client preserves running processes;
a machine restart restores saved layout and resumes supported Claude/Codex
conversations captured by the installed SessionStart integrations. Start or
resume those agents inside Herdr after activation so their IDs are captured.
`python3 tests/herdr-integrations.py` checks the installed hooks against an
isolated socket. Codex may request review of a changed hook in `/hooks`.

[Auto Title](https://github.com/kryptamine/herdr-auto-title) names top tabs
from the directory and current terminal task title, keeping the shortcut number
first. Agent names are omitted because the sidebar already shows them. Manual
tab names are preserved; clear a tab's name to resume automatic naming.
The plugin and its configuration are managed by `home/herdr.nix` on both Macs.
It starts with the Herdr server. For the first activation into an already-running
server, invoke `herdr plugin action invoke herdr.auto-title.start` once, after
checking `herdr plugin log list --plugin herdr.auto-title` has no running entry.
This starts naming without stopping any panes. Configuration is read on plugin
startup, from `~/Library/Application Support/herdr-auto-title/config.env` on macOS
or `$XDG_CONFIG_HOME/herdr-auto-title/config.env` on Linux.

## Manual setup steps (per host)

Everything nix *cannot* do, per machine — TCC grants, first-boot quirks,
one-time app setup, bootstrap order:

* **MacBook Air**: [MANUAL-macbook-air.md](MANUAL-macbook-air.md)
* **Mac mini (headless, from scratch)**: [MANUAL-mac-mini.md](MANUAL-mac-mini.md)
