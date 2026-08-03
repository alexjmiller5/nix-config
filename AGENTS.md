# nix-config

Declarative config for Alex's Macs: nix-darwin + home-manager, nixpkgs-unstable.
Hosts: `macbook-air` (daily driver, full profile) and `mac-mini` (headless
server). The `nix` skill (wrapper → nix-mechanics + dev-env) carries the full
routing table and workflow; this file is the in-repo map.

## Layout

- `flake.nix` — `mkHost { host, home }`; exports `homeModules.*` for external
  flakes (planned work-laptop config pins this repo)
- `hosts/*.nix` — system layer: brew taps/brews/casks/masApps (zap cleanup:
  the lists ARE the machine), power, per-host defaults
- `home/` — home-manager modules by concern: `common` (shared packages, git
  via `git.nix`), `zsh.nix` (full shell + starship), `aliases/{dev,ai,infra}`,
  `agents.nix` (launchd: private-repo sync, weekly updates, login items),
  `macos-tweaks.nix` (activation-script defaults: currentHost, duti, xattr),
  `ssh.nix` (programs.ssh + private Include), `reference-repos.nix`,
  per-host `macbook-air.nix` / `mac-mini.nix`
- `modules/` — darwin modules shared across hosts (`macos-defaults.nix`, `notunes.nix`)
- `dotfiles/` — file payloads (ghostty, karabiner, nvim, vscode, ssh pubs, duti list)
- `secrets/` — agenix (recipients in `secrets.nix`; edit with `-i ~/.ssh/agenix`)
- `MANUAL-macbook-air.md` — every step nix cannot do (TCC, SIP, sign-ins, bootstrap order)

## Conventions

- **File-management modes, chosen per file**: generated from options (zsh,
  git) > store symlink from `dotfiles/` (configs apps never write) >
  `mkOutOfStoreSymlink` into a companion working clone (files apps DO write:
  VS Code settings, Claude config/skills). Never manage runtime auth state
  (`~/.claude.json`, `gh hosts.yml`).
- **Privacy split**: this repo is PUBLIC. Personal context → `agent-config`
  repo; runtime values with hostnames/IPs → `nix-secrets` repo (ssh Include).
- nixpkgs first for CLI tools (verify attr names — brew names differ:
  sevenzip→`_7zz`, yq→`yq-go`); brew for casks and brew-only formulae.
- New files must be `git add`ed before `nix build` sees them (flake rule).

## Verify + apply

```bash
just check                                            # nix flake check
nix build .#darwinConfigurations.macbook-air.system   # proof-build (laptop)
nix build .#darwinConfigurations.mac-mini.system      # proof-build (mini)
```

Agents never activate: `just switch-laptop` (laptop) and `just deploy` (mini)
need Alex's sudo — ask him. Never activate a host you're not on.
