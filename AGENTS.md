# nix-config

Declarative config for Alex's Macs: nix-darwin + home-manager, nixpkgs-unstable.
Hosts: `macbook-air` (daily driver, full profile) and `mac-mini` (headless
server). The `nix` skill (wrapper → nix-mechanics + dev-env) carries the full
routing table and workflow; this file is the in-repo map.

## Layout

* `flake.nix` — `mkHost { host, home }`; exports `homeModules.*` for external
  flakes (planned work-laptop config pins this repo); `formatter` = nixfmt-tree
  (`just fmt`)
* `hosts/*.nix` — system layer DIFFS from `modules/darwin-base.nix`: brew
  taps/brews/casks/masApps (zap cleanup: the lists ARE the machine), power,
  per-host defaults
* `home/` — home-manager modules by concern: `common` (base identity; pulls
  `git.nix`, `git-signing.nix`, `scripts.nix`, `cli-tools.nix`, `op-wrappers.nix`,
  `agent-config-links.nix`, `machine-vault-git.nix`, `mcp.nix`),
  `zsh.nix` (full shell + starship), `aliases/{dev,ai,infra}`,
  `agent-env.nix` (shared detection and credential initialization in `.zshenv`
  and `~/.config/agent-shell/env.sh`, sourced by Claude's per-tool adapter;
  `AGENT_OP_AUTH=desktop` prevents SA loading through nested shells and wrappers),
  `git-signing.nix` (shared signing settings, `.agents/skills` signer),
  `mcp.nix` (one `programs.mcp.servers` registry generates the native MCP
  plugin loaded by both Claude and Codex; direct Codex MCP entries stay app-owned),
  `op-wrappers.nix` (the op-authed CLI shadow family: gh, modal, gog, wacli,
  wrangler, gcloud, ntn, posthog-cli - AI Agent vault creds in every context, read per call
  so nothing credential-shaped touches disk. Every op call in the family sits
  behind `op_has_auth` (agent-op-env.sh) - with no auth source at all, op
  prompts on /dev/tty and hangs headless callers. `opConnect.cliPackage`
  routes supported AI Agent vault reads through local Connect when enabled.
  Writes, documents, other vaults, explicit project SAs and desktop auth
  keep the direct path. Direct SA rate limits still require the `1password`
  skill's desktop-auth protocol),
  `op-connect.nix` (opt-in, exported local Docker Desktop deployment, enabled
  on the laptop. Official API/sync images share Connect's encrypted cache;
  API binds only 127.0.0.1. A login service restores the encrypted credentials
  Document when absent, reads the Connect token once through the independently
  enrolled agent SA (never the machine bootstrap SA),
  opens Docker and starts Compose. The token stays in memory behind a 0600
  Unix socket, delivered only to the op child process. No token in shell init,
  Docker environment, Git, Nix store or an additional plaintext file.
  `op-connect-start` restarts the login service after rotation or failure;
  supported reads fail closed when it is unavailable. `op run`/`inject` and
  item reads without explicit vault ID plus JSON format remain direct.
  Its launch PATH includes /usr/sbin and /sbin: Docker's privileged-helper
  installer invokes /sbin/md5 by name),
  `posthog-auth.sh` (PostHog credential aliases and API-host normalization;
  the agent CLI uses the existing broad AI Agent key. Explicit
  `POSTHOG_CLI_API_KEY` / `POSTHOG_CLI_HOST` override it; an app's public
  ingestion token does not. `pkgs/posthog-cli.nix` pins the official binary,
  Node API bundle, and upstream skills exposed at
  `$XDG_DATA_HOME/posthog/skills` with the usual `~/.local/share` default),
  `agent-config-links.nix` (the agent-config fan-out symlinks, one list for
  both machines),
  `claude-plugins.nix` (Claude Code plugins as pinned flake inputs, linked
  into the agent-config skills dir and loaded in place via `@skills-dir`:
  `claude plugin install` is imperative and `enabledPlugins` never fetches
  anything, so a restored machine got none; git-ignored on the agent-config
  side),
  `codex.nix` (Codex CLI - the ChatGPT-subscription seat; skills and
  AGENTS.md are left to `agent-config-links.nix` so both stay editable
  without a rebuild, and `programs.codex.context` stays at its "" default
  so the module writes no competing AGENTS.md),
  `machine-vault-git.nix` (per-host options for explicit initial cloning via
  `bootstrap-companion-repos`; machine PAT helper passed only to individual
  allowed clones, never installed in Git config or run by activation),
  `dev-tools.nix` (portable dev toolbox + memo wrapper, shared by BOTH
  hosts — laptop-only tooling stays in `macbook-air.nix`),
  `herdr.nix` (native `programs.herdr` settings and Claude/Codex session
  restoration hooks shared by both hosts; Claude's installer runs during
  activation against its writable settings, while Codex hooks are HM-managed;
  `ghostty.nix` adds `herdr-window`, which claims its window for the
  Hammerspoon hotkeys that translate macOS tab/split shortcuts into Herdr
  prefix keys (pinned in `herdr.nix`). The pinned Undo Close plugin
  restores closed tabs through Cmd+Shift+T, mapped to prefix+t. Cmd+W snapshots
  the current agent sessions before closing; the plugin patch adds this action
  and Codex resume support. Closed panes are excluded from its history.
  Native selection copying stays enabled; clipboard feedback comes from
  Hammerspoon, so Herdr's clipboard toast is disabled. The pinned Auto Title
  plugin provides fallback top-tab names capped at 24 columns, omits redundant
  agent names, and preserves custom labels. Agents follow global AGENTS.md to
  write their own 2-3 word task names without separate model calls.
  The packaged `herdr.auto-title.start` action can start it in a live server;
  check plugin logs first to avoid starting a duplicate),
  `agents.nix` (launchd: companion-repo sync (agent-config + agent-config-public), weekly updates, login items;
  both hosts' repo-sync jobs set `AGENT_SHELL=repo-sync` so the gh wrapper
  uses the independently enrolled AI Agent token without shell startup; the
  sync repairs mangled SKILL.md frontmatter before staging, since that damage
  silently disables a skill and has twice ridden a snapshot into history),
  `ai-agent.nix` (node for hooks, `op` on PATH and `agent-env.nix` for
  independently enrolled operator credentials. The existing 0600
  `~/.local/state/op/agent-sa-token` interface serves agent shells, agent SSH
  and Connect without a login Keychain. Enrollment/rotation belongs to the
  AI Agent credential owner, using native user authentication and its
  authoritative record, separate from Nix bootstrap; see both host manuals.
  Nix never populates or refreshes this file. Claude/Codex subscription login
  remains native app state, separate from operator tool credentials.
  Host-layer sibling = `claude-code` + `notion-cli` casks),
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
* `secrets/` - agenix: exactly ONE secret per machine (its 1P machine-vault
  SA token). Machine vaults and their service accounts are exclusively for
  initial Nix bootstrap. Applications own enrollment, credential storage
  and recovery through their supported interfaces. Git uses the machine
  vault only through the explicit initial bootstrap command. Routine pulls,
  pushes and switches do not invoke its credential helper.
  Life background sync imports its own device token once into Keychain via
  the installed CLI. Edit = recreate-not-decrypt (see
  `secrets/secrets.nix` header); no master key exists.
* Moshi on the Mini uses its declared Homebrew formula/service and native
  pairing store. Nix does not restore or rewrite Moshi credentials. Existing
  machines retain their pairing; replacement machines pair through Moshi.
  The Air does not install the Moshi daemon. Claude/Codex hook wiring stays
  declared independently of pairing.
* `MANUAL-macbook-air.md`, `MANUAL-mac-mini.md` - steps outside Nix (TCC,
  SIP, sign-ins, bootstrap order), including Life browser enrollment, desktop
  Keychain setup and verification after replacing a machine.

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

Activate with `just switch-laptop` (laptop) or `just deploy` (mini) - both
passwordless via the NOPASSWD sudoers rule in `modules/darwin-base.nix`, so
agents run them directly after a green proof-build. Never activate a host
you're not on.
