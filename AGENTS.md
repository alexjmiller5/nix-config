# nix-config

Declarative config for Alex's Macs: nix-darwin + home-manager, nixpkgs-unstable.
Hosts: `macbook-air` (daily driver, full profile) and `mac-mini` (headless
server). The `nix` skill (wrapper → nix-mechanics + dev-env) carries the full
routing table and workflow; this file is the in-repo map.

## Layout

* `flake.nix` — `mkHost { host, home }`; exports `homeModules.*` for external
  flakes (planned work-laptop config pins this repo)
* `hosts/*.nix` — system layer: brew taps/brews/casks/masApps (zap cleanup:
  the lists ARE the machine), power, per-host defaults
* `home/` — home-manager modules by concern: `common` (base identity; pulls
  `git.nix`, `scripts.nix`, and `cli-tools.nix`'s shared package list),
  `zsh.nix` (full shell + starship), `aliases/{dev,ai,infra}`,
  `agents.nix` (launchd: private-repo sync, weekly updates, login items),
  `ai-agent.nix` (one-import AI-agent readiness: node for hooks, `op` on
  PATH, and `op-agent-sa.nix` — login-time refresh of the agent SA token
  from the machine vault into a 0600 file, `~/.local/state/op/agent-sa-token`;
  a file, not the Keychain, since ssh-descended shells can't read the
  per-session-locked Keychain; host-layer sibling = `claude-code` +
  `notion-cli` casks),
  `macos/{menu-bar,duti,nightlight,spotlight-raycast,chrome-extension-storage,chrome-remote-debugging}.nix`
  (activation-script defaults by concern, each exported via `homeModules`),
  `ssh.nix` (programs.ssh + private Include),
  `scripts.nix` (standalone commands as writeShellApplication — shell-state
  functions and command shadows stay in `zsh/functions.zsh`),
  per-host `macbook-air.nix` / `mac-mini.nix`
* `modules/` — darwin modules: `macos-defaults.nix` (injected for every host by mkHost), `notunes.nix` (laptop-only import)
* `dotfiles/` — file payloads (karabiner, nvim, vscode, ssh pubs, duti list)
* `secrets/` — agenix: exactly ONE secret per machine (its 1P machine-vault
  SA token); all other secrets live in the per-machine 1P vaults, fetched at
  runtime via `op read` by ID. Edit = recreate-not-decrypt (see
  `secrets/secrets.nix` header); no master key exists.
* `MANUAL-macbook-air.md` — every step nix cannot do (TCC, SIP, sign-ins, bootstrap order)

## Conventions

* **File-management modes, chosen per file**: native HM module
  (`programs.*` — check it exists via mcp-nixos before falling back; zsh,
  git, ssh, neovim, fzf, ghostty, spotify-player, vscode) > store symlink
  from `dotfiles/` (configs apps never write and no module covers) >
  `mkOutOfStoreSymlink` into a companion working clone (files apps DO write:
  VS Code settings, Claude config/skills). Never manage runtime auth state
  (`~/.claude.json`, `gh hosts.yml`).
* **Privacy split**: this repo is PUBLIC. Personal context → `agent-config`
  repo; runtime values with hostnames/IPs → `nix-secrets` repo (ssh Include).
* nixpkgs first for CLI tools (verify attr names — brew names differ:
  sevenzip→`_7zz`, yq→`yq-go`); brew for casks and brew-only formulae.
* New files must be `git add`ed before `nix build` sees them (flake rule).

## Verify + apply

```Shell
just check                                            # nix flake check
nix build .#darwinConfigurations.macbook-air.system   # proof-build (laptop)
nix build .#darwinConfigurations.mac-mini.system      # proof-build (mini)
```

Agents never activate: `just switch-laptop` (laptop) and `just deploy` (mini)
need Alex's sudo — ask him. Never activate a host you're not on.
