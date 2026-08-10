# MANUAL-macbook-air.md — MacBook steps nix cannot do

Everything on the laptop that can't be declared, in bootstrap order. (The
mini's equivalent lives in README.md §Manual setup steps.) Sources: blueprint's
MANUAL\_STEPS.md + its TCC snapshot, and the 2026-07/08 migration itself.

## Fresh-machine bootstrap order

Written for total loss (laptop in the ocean): nothing survives but GitHub,
1Password, and the mini. The replacement machine's SSH host key is new, so
the laptop `.age` secrets must be recreated for it BEFORE the first switch —
that's the only reason bootstrap needs a local clone instead of building
straight from the github: ref.

1. Sign in Apple ID; sign into the **App Store** (masApps installs need it).
2. Install [Determinate Nix](https://install.determinate.systems).
3. Clone this repo (public — no auth) and enroll the new machine's host key:
   ```Shell
   nix run nixpkgs#git -- clone https://github.com/alexjmiller5/nix-config ~/.config/nix-config
   cd ~/.config/nix-config
   cat /etc/ssh/ssh_host_ed25519_key.pub   # → paste over laptopHost in secrets/secrets.nix
   ```
   Then recreate the laptop's ONE secret — the `macbook-air-machine` 1P
   service-account token — for the new key (recreate-not-decrypt — no master
   key, no rekey; encryption needs only the public keys in secrets.nix). Read
   the token from the 1Password **web vault** (1password.com in Safari — the
   1P app isn't installed until the first switch; the SA token item lives in
   the "MacBook Air" vault). Every other secret (git PAT, future ones) is
   fetched from that vault at runtime via `op read`, so this is the only
   paste:
   ```Shell
   cd secrets && rm machine-sa-laptop.age
   EDITOR=nano nix run github:ryantm/agenix -- -e machine-sa-laptop.age   # paste SA token from 1P web
   cd .. && nix run nixpkgs#git -- add -A   # flakes only see tracked files
   ```
4. First switch, from the local tree:
   ```Shell
   nix build .#darwinConfigurations.macbook-air.system
   sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook-air
   ```
   Activation decrypts the token onto the agenix RAM disk, the git credential
   helper goes live, and `/etc/nix-darwin` links to the clone — from here on
   the `switch-laptop` alias works from anywhere.
5. Sign into the 1Password app (installed by the switch); `op signin`; then
   `op plugin init gh` so interactive `gh` rides 1P per-invocation. There is
   NO `gh auth login` — git auth is the agenix PAT, and no token enters the
   keychain.
6. `switch-laptop` again — activation now clones the private companions
   (agent-config, nix-secrets, hammerspoon) via the credential helper, and
   the out-of-store symlinks resolve.
7. Commit + push the step-3 changes (secrets.nix + the recreated .age) — push
   auth works now.
8. Trust the third-party taps (brew's tap-trust gate blocks formula loads
   otherwise): `for t in alexjmiller5/tap asmvik/formulae ddev/ddev electrikmilk/cherri jellycuts/formulae koekeishiya/formulae smudge/smudge steipete/tap supabase/tap; do brew trust "$t"; done`

## Machine vaults (1P) — the secret architecture

Each machine has a 1P vault ("MacBook Air" / "Mac Mini") and a read-only
service account (`macbook-air-machine` / `mac-mini-machine`). agenix encrypts
exactly ONE secret per machine — its SA token — and everything else lives in
the machine vault, fetched at runtime with `op read` (by vault/item **ID**,
never name). Adding or rotating a secret = edit the 1P item; the repo and the
machines don't change.

In the vaults today:

* **MacBook Air**: `GitHub PAT nix-config-git-laptop` — fine-grained, repos
  `agent-config`/`nix-secrets`/`hammerspoon`, Contents **read/write** (the
  sync agent pushes agent-config). Feeds the git credential helper.
* **Mac Mini**: `GitHub PAT nix-config-git-mini` — same repos, Contents
  **read-only** (the mini is pull-only by design); plus the finance-project
  SA token (read at run time by notion-finance-sync).

PATs are minted by hand (GitHub has no token-creation API): github.com →
Settings → Developer settings → Fine-grained tokens; they cap at 1-year
expiry, so re-mint + update the 1P item annually — no repo commit, no
rebuild. Machine lost = revoke that machine's SA (1P dashboard), drop its
pubkey from secrets.nix, recreate its .age; the vault contents rotate at
leisure since the SA token was the only thing the disk could yield.

## TCC grants (System Settings → Privacy & Security; GUI-only by design)

* **Accessibility**: Hammerspoon, Karabiner-Elements, yabai, AltTab, Raycast,
  BetterDisplay, Ghostty, VS Code, Claude
* **Input Monitoring**: Karabiner-Elements, Ghostty, VS Code
* **Screen Recording**: AltTab, 1Password, Raycast, Notion
* **Full Disk Access**: VS Code, Ghostty, Raycast
* **Automation**: Ghostty/Terminal/VS Code → System Events; Hammerspoon; Docker

## yabai (SIP + sudoers)

1. Recovery mode: `csrutil enable --without fs --without debug --without nvram`,
   then `sudo nvram boot-args=-arm64e_preview_abi`.
2. Sudoers entry for the scripting addition (hash changes on every yabai
   update — regenerate then):
   `echo "$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 $(which yabai) | cut -d' ' -f1) $(which yabai) --load-sa" | sudo tee /private/etc/sudoers.d/yabai`
3. `yabai --start-service` (the custom `com.asmvik.yabai` launchd plist is a
   deliberate imperative leftover).

## App sign-ins (after first switch; GUI-only, none scriptable)

* **1Password** — covered in bootstrap step 5 (app sign-in, `op signin`,
  `op plugin init gh`).
* **Claude** — sign into the Claude desktop app and Claude Code (`claude` →
  `/login`); auth state lands in `~/.claude.json` (deliberate leftover).
* **Notion** — sign into the desktop app.
* **VS Code** — sign into GitHub in-app (Copilot etc.). No Settings Sync —
  settings/keybindings are nix-managed.
* **WhatsApp** — pair from the phone (Settings → Linked Devices → QR).
* **Spotify** — sign into the desktop app. Separately, run
  `spotify_player authenticate` once (interactive browser OAuth; needs
  Premium) — tokens then self-refresh from `~/.cache/spotify-player/`.
  Agents can't do this step (see `spotify` skill).
* **Google accounts** — System Settings → Internet Accounts: account list,
  addresses, and per-service toggles live in nix-secrets
  `manual/google-accounts.md` (public-repo privacy rule).

## One-time app/setting setup

* **Accessibility → Zoom**: enable scroll-gesture-with-modifier zoom (ctrl) —
  `com.apple.universalaccess` is FDA-gated, not worth automating.
* **Hammerspoon**: console → `hs.ipc.cliInstall("/opt/homebrew")`; preferences →
  hide dock icon.
* **Chrome**: load-unpacked extensions (bypass-paywalls et al from
  `~/Desktop/coding/built-from-source`); per-PWA "open links in Chrome".
* **1Password** app settings can't be restored from backup (checksummed) —
  configure by hand.
* **Raycast**: clipboard history retention → 7 days; custom extensions load
  from their dev source directories.
* **Own apps**: build Synapse macOS app + Receptor from source → /Applications.
* **Nightlight**: the activation script needs a display connected on first run.

## Menu bar: what's declared vs manual

Declared: dock order (`hosts/macbook-air.nix` dock block), system icon
visibility (ByHost ints in `home/macos/menu-bar.nix` menuBarModules — macOS 26
ignores the legacy plain-domain "NSStatusItem Visible" keys), and system
icon ORDER via the `menubar-layout` command (declared in
`home/macbook-air.nix`; run it whenever the system modules drift — it's
on-demand, not activation, because ControlCenter renormalizes the position
numbers after each layout and enforcing exact values every switch would
flap).

Manual: THIRD-PARTY icon order (⌘-drag). Can't sanely be declared: each
app's spot is an `"NSStatusItem Preferred Position"` pixel-offset key in
that app's own defaults domain, reread only at app launch — and apps that
skip `autosaveName` (e.g. CodexBar) get no position persistence from macOS
at all. If arrangement drift ever gets annoying, the Thaw cask
(Accessibility-based layout profiles) is the tool-shaped answer. Full
research: Notion note "Menu bar / dock in nix — findings" (2026-08-02).

Reference layout, right → left (snapshotted 2026-08-04): clock,
Control Center, Sound, WiFi, BetterDisplay, Tailscale, Battery, Bluetooth,
Screen Mirroring, Weather, 1Password, AirDrop, Synapse, RepoBar, CodexBar.

## Known imperative leftovers (deliberate)

* `com.asmvik.yabai.plist`, `com.alexmiller.geminidesktop.plist`, OpenClaw
  agents — owned by their own projects, not this repo.
* `/Applications/eggnoggplus.app` — EGGNOGG+ (madgarden). No cask exists and
  the itch.io download has no stable URL, so it can't be declared without
  rehosting the binary. Kept as a manual install; zap ignores non-brew apps.
  Reinstall from https://madgarden.itch.io/eggnogg.
* `gcloud`/`op` credentials, `~/.claude.json`, `~/.config/op/plugins` (the
  `op plugin init gh` state) — runtime auth state, never declared. git's
  GitHub auth is NOT in this list anymore: it's the agenix PAT.

