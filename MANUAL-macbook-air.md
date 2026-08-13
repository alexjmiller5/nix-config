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
5. Sign into the 1Password app (installed by the switch); `op signin`. There
   is NO `gh auth login` and no `op plugin` setup — git auth is the agenix
   PAT, `gh`/`gcloud` are the op-authed PATH wrappers, and no token enters
   the keychain.
6. `switch-laptop` again — activation now clones the private companions
   (agent-config, nix-secrets, hammerspoon) via the credential helper, and
   the out-of-store symlinks resolve.
7. Commit + push the step-3 changes (secrets.nix + the recreated .age) — push
   auth works now.
8. Trust the third-party taps (brew's tap-trust gate blocks formula loads
   otherwise): `for t in alexjmiller5/tap asmvik/formulae ddev/ddev electrikmilk/cherri jellycuts/formulae smudge/smudge steipete/tap supabase/tap; do brew trust "$t"; done`

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

Snapshot verified against the system TCC db 2026-08-13. Audit anytime with:

```Shell
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT service, client FROM access WHERE auth_value > 0 AND service IN
   ('kTCCServiceAccessibility','kTCCServiceListenEvent',
    'kTCCServiceScreenCapture','kTCCServiceSystemPolicyAllFiles')
   ORDER BY service, client;"
```

* **Accessibility**: Hammerspoon, Karabiner-Elements, yabai (the nix store
  binary — re-grant on version bumps), AltTab, Raycast, Raycast Beta,
  BetterDisplay, Ghostty, VS Code, Claude, 1Password, Discord, Zoom
* **Input Monitoring**: Karabiner-Elements (grants land on its helper
  binaries), Dolphin
* **Screen Recording**: AltTab, 1Password, Notion, Claude, Chrome,
  VS Code, Ghostty, Telegram, Zoom
* **Full Disk Access**: VS Code, Ghostty, Raycast, Raycast Beta,
  /bin/zsh (launchd/agent shell scripts)
* **Automation**: Ghostty/Terminal/VS Code → System Events; Hammerspoon; Docker

Path-keyed clients (nix-store yabai, brew's versioned node/claude-code paths)
re-key on every version bump: yabai needs its Accessibility re-grant, the
others just shed a dead row. Harmless — purge dead rows whenever auditing.

## yabai (SIP only — the rest is declared)

The agent, scripting-addition loader, and sudoers entry are all declarative
(`services.yabai` in `hosts/macbook-air.nix`). What stays manual:

1. Recovery mode: `csrutil enable --without fs --without debug --without nvram`,
   then `sudo nvram boot-args=-arm64e_preview_abi`.
2. Accessibility grant (below) — and RE-grant after any yabai version bump:
   the nix store path (and the binary TCC keys on) changes with each update.

## App sign-ins (after first switch; GUI-only, none scriptable)

* **1Password** — covered in bootstrap step 5 (app sign-in, `op signin`).
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
* **Chrome**: load-unpacked extensions — Developer mode ON, then Load
  unpacked for each: bypass-paywalls et al from
  `~/Desktop/coding/built-from-source`, and own `chrome-extension`-template
  projects from their repo's `extension/` dir (upcoming:
  bookmark-extension-sync). NOTE the default-deny policy: an unpacked
  extension loads only if its path-derived ID has an `allowed` entry in the
  `ExtensionSettings` block. Store extensions and PWAs need NO manual steps —
  installed by the Chrome policy plist (`ExtensionSettings` +
  `WebAppInstallForceList`, written to Managed Preferences by the activation
  script in `hosts/macbook-air.nix`). Per-PWA "open links in Chrome".
* **1Password** app settings can't be restored from backup (checksummed) —
  configure by hand.
* **Raycast**: clipboard history retention → 7 days; extensions → see
  "Raycast extensions" section below.
* **Nightlight**: the activation script needs a display connected on first run.

## Raycast extensions (undeclarable — this list IS the declaration)

Raycast registers installed extensions in an encrypted local DB
(`raycast-enc.sqlite`, SQLCipher) with no CLI/API/deeplink to install
headlessly, so extensions can't be nix-managed. Keep this list current when
installing/removing; regenerate it with the "Installed Extensions" store
extension and diff against this section.

Store extensions — install via Raycast Store or `https://raycast.com/<slug>`:

`DanielSinclair/base64` · `mooxl/coffee` · `thomas/color-picker` ·
`priithaamer/docker` · `ron-myers/facetime` · `hrishabhn/flighty` ·
`josephschmitt/gif-search` · `destiner/iconify` ·
`pernielsentikaer/installed-extensions` · `shldk/macosicons` ·
`Melvynx/qrcode-generator` · `maantje/remove-background` ·
`tegola/remove-paywall` · `benvp/audio-device` · `mattisssa/spotify-player` ·
`1weiho/svgl` · `hossammourad/raycast-system-monitor` · `ThatNerd/timers` ·
`iamyeizi/toggle-menu-bar` · `VladCuciureanu/toothpick` · `eggsy/unsplash` ·
`truex/whosampled` · `raycast/zoom`

Custom-built (modified store forks, dev-imported, NOT from the store;
clone to these paths):

* Git Repos — `~/Desktop/coding/active-projects/raycast-git-repos`
  (github.com/alexjmiller5/raycast-git-repos)
* Messages — `~/Desktop/coding/active-projects/raycast-messages`
  (github.com/alexjmiller5/raycast-messages)

Restore: install each store extension from the Store; for the two custom
ones run `npm ci && npx ray develop` in each dir, then Ctrl-C once loaded
(the dev import persists without the watcher).

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
Screen Mirroring, Weather, 1Password, AirDrop, RepoBar, CodexBar.

## Known imperative leftovers (deliberate)

* `/Applications/Raycast Beta.app` — manual download from raycast.com (no
  cask exists for the beta channel; it self-updates). Its login item IS
  declared (`home/agents.nix`); only the install itself is manual. Stable
  Raycast stays alongside it as the declared `raycast` cask.
* `gcloud`/`op` credentials, `~/.claude.json` — runtime auth state, never
  declared. git's GitHub auth is NOT in this list anymore: it's the agenix PAT.

