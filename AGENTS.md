# nix-config

Declarative config for Alex's Macs: nix-darwin + home-manager, nixpkgs-unstable.
Hosts: `macbook-air` (daily driver, full profile) and `mac-mini` (headless
server). The `nix` skill (wrapper → nix-mechanics + dev-env) carries the full
routing table and workflow; this file is the in-repo map.

## Layout

* `flake.nix` — `mkHost { host, home }`; exports `homeModules.*` for external
  flakes (planned work-laptop config pins this repo); `formatter` = nixfmt
  (RFC 166 — `just fmt`)
* `hosts/*.nix` — system layer DIFFS from `modules/darwin-base.nix`: brew
  taps/brews/casks/masApps (zap cleanup: the lists ARE the machine), power,
  per-host defaults
* `home/` — home-manager modules by concern: `common` (base identity; pulls
  `git.nix`, `scripts.nix`, `cli-tools.nix`, `op-wrappers.nix`,
  `agent-config-links.nix`, `machine-vault-git.nix`, `mcp.nix`),
  `zsh.nix` (full shell + starship), `aliases/{dev,ai,infra}`,
  `op-wrappers.nix` (the op-authed CLI shadow family: gh, modal, gog,
  gcloud — AI Agent vault creds in every context; gh/modal read through
  `op-cache.sh`'s TTL cache because 1Password meters service accounts at
  1000 requests/24h **per 1Password account**, shared across every SA — a
  per-call `op read` in a hot wrapper exhausts the day, and minting another
  SA does not help),
  `agent-config-links.nix` (the agent-config fan-out symlinks, one list for
  both machines),
  `claude-plugins.nix` (Claude Code plugins as pinned flake inputs, linked
  into the agent-config skills dir and loaded in place via `@skills-dir` —
  `claude plugin install` is imperative and `enabledPlugins` never fetches
  anything, so a restored machine got none; git-ignored on the agent-config
  side),
  `machine-vault-git.nix` (per-host options: repo-scoped machine-vault PAT
  credential helper + companion clone-if-missing),
  `dev-tools.nix` (portable dev toolbox + memo wrapper, shared by BOTH
  hosts — laptop-only tooling stays in `macbook-air.nix`),
  `agents.nix` (launchd: private-repo sync, weekly updates, login items; the
  sync repairs mangled SKILL.md frontmatter before staging, since that damage
  silently disables a skill and has twice ridden a snapshot into history),
  `ai-agent.nix` (one-import AI-agent readiness: node for hooks, `op` on
  PATH, and `op-agent-sa.nix` — login-time refresh of the agent SA token
  from the machine vault into a 0600 file, `~/.local/state/op/agent-sa-token`;
  a file, not the Keychain, since ssh-descended shells can't read the
  per-session-locked Keychain; host-layer sibling = `claude-code` +
  `notion-cli` casks),
  `macos/{menu-bar,duti,nightlight,spotlight-raycast,chrome-extension-storage,chrome-remote-debugging,notification-prefs}.nix`
  (activation-script defaults by concern, each exported via `homeModules`),
  `ssh.nix` (programs.ssh + private Include),
  `scripts.nix` (standalone commands as writeShellApplication — shell-state
  functions and command shadows stay in `zsh/functions.zsh`),
  per-host `macbook-air.nix` / `mac-mini.nix`
* `modules/` — darwin modules: `darwin-base.nix` + `macos-defaults.nix`
  (both injected for every host by mkHost), `chrome-policy.nix` (declared
  extension set + PWAs, laptop-only import), `notunes.nix` (laptop-only import)
* `pkgs/` — custom package derivations (`callPackage`d from home files)
* `dotfiles/` — file payloads (karabiner, nvim, vscode, ssh pubs, duti list)
* `secrets/` — agenix: exactly ONE secret per machine (its 1P machine-vault
  SA token); all other secrets live in the per-machine 1P vaults, fetched at
  runtime via `op read` by ID. Edit = recreate-not-decrypt (see
  `secrets/secrets.nix` header); no master key exists.
* `MANUAL-macbook-air.md` — every step nix cannot do (TCC, SIP, sign-ins, bootstrap order)

## Conventions

* **Two-machine parity rule**: every change to a host file or per-host home
  profile must explicitly consider the OTHER machine — does this belong on
  both (→ a shared module: `dev-tools`, `cli-tools`, `ai-agent`, ...), or on
  one only, and why? State the answer when making the change, and when it
  isn't obvious, ASK Alex before committing. Never let a capability land on
  one machine just because that's where it was developed — that's how the
  configs drifted apart before.

* **File-management modes, chosen per file**: native HM module
  (`programs.*` — check it exists via mcp-nixos before falling back; zsh,
  git, ssh, neovim, fzf, ghostty, spotify-player, vscode) > store symlink
  from `dotfiles/` (configs apps never write and no module covers) >
  `mkOutOfStoreSymlink` into a companion working clone (files apps DO write:
  VS Code settings, Claude config/skills). Never manage runtime auth state
  (`~/.claude.json`, `gh hosts.yml`) — sole exception: `ai-agent.nix`'s
  activation script seeds the home-dir trust flag into `~/.claude.json`
  (Claude Code won't persist it itself); it merges that one key and owns
  nothing else in the file.
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
