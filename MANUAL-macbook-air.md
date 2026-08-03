# MANUAL-macbook-air.md — MacBook steps nix cannot do

Everything on the laptop that can't be declared, in bootstrap order. (The
mini's equivalent lives in README.md §Manual setup steps.) Sources: blueprint's
MANUAL_STEPS.md + its TCC snapshot, and the 2026-07/08 migration itself.

## Fresh-machine bootstrap order

1. Sign in Apple ID; sign into the **App Store** (masApps installs need it).
2. Install [Determinate Nix](https://install.determinate.systems), then
   bootstrap straight from GitHub — no clone needed (this repo is public):
   ```bash
   nix build github:alexjmiller5/nix-config#darwinConfigurations.macbook-air.system
   sudo ./result/sw/bin/darwin-rebuild switch --flake github:alexjmiller5/nix-config#macbook-air
   ```
   Activation clones `~/.config/nix-config` itself (companion-repos, in
   home/macbook-air.nix) and links `/etc/nix-darwin` to it, so from here on
   the `switch-laptop` alias works from anywhere.
3. `gh auth login`, sign into the 1Password app, `op signin` once.
4. `switch-laptop` again — activation now clones the private companions
   (agent-config, nix-secrets, hammerspoon) via gh's auth, and the
   out-of-store symlinks resolve.
5. Trust the third-party taps (brew's tap-trust gate blocks formula loads
   otherwise): `for t in asmvik/formulae ddev/ddev electrikmilk/cherri jellycuts/formulae koekeishiya/formulae smudge/smudge steipete/tap supabase/tap; do brew trust "$t"; done`

## SSH + secrets — zero manual keys

Everything is declared: programs.ssh + nix-secrets Include, .pub selectors,
mini authorized_keys. No agenix key exists on the laptop — none is needed:

- **Rotating/editing a secret** = recreate, not decrypt (encryption uses only
  the public keys in `secrets/secrets.nix`; the value's source of truth is
  1Password): `cd secrets && rm op-token.age && EDITOR=nano nix run
  github:ryantm/agenix -- -e op-token.age` → paste from 1P, save, commit, deploy.
- **Viewing a secret's current value** → look in 1Password (only the mini can
  decrypt, via its host key, at activation).

## TCC grants (System Settings → Privacy & Security; GUI-only by design)

- **Accessibility**: Hammerspoon, Karabiner-Elements, yabai, AltTab, Raycast,
  BetterDisplay, Ghostty, VS Code, Claude
- **Input Monitoring**: Karabiner-Elements, Ghostty, VS Code
- **Screen Recording**: AltTab, 1Password, Raycast, Notion
- **Full Disk Access**: VS Code, Ghostty, Raycast
- **Automation**: Ghostty/Terminal/VS Code → System Events; Hammerspoon; Docker

## yabai (SIP + sudoers)

1. Recovery mode: `csrutil enable --without fs --without debug --without nvram`,
   then `sudo nvram boot-args=-arm64e_preview_abi`.
2. Sudoers entry for the scripting addition (hash changes on every yabai
   update — regenerate then):
   `echo "$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 $(which yabai) | cut -d' ' -f1) $(which yabai) --load-sa" | sudo tee /private/etc/sudoers.d/yabai`
3. `yabai --start-service` (the custom `com.asmvik.yabai` launchd plist is a
   deliberate imperative leftover).

## One-time app/setting setup

- **Login items**: keep System Settings → Open at Login EMPTY (nix launchd
  agents own app startup). Also uncheck the in-app "launch at login" toggles —
  1Password, Raycast, Raycast Beta, BetterDisplay, Hammerspoon, CodexBar,
  RepoBar — or they re-register themselves. FigmaAgent is Figma-managed; leave it.
- **Screen Time**: enable "Share across devices" (feeds iOS data to the mac).
- **Accessibility → Zoom**: enable scroll-gesture-with-modifier zoom (ctrl) —
  `com.apple.universalaccess` is FDA-gated, not worth automating.
- **Hammerspoon**: console → `hs.ipc.cliInstall("/opt/homebrew")`; preferences →
  hide dock icon.
- **Chrome**: load-unpacked extensions (bypass-paywalls et al from
  `~/Desktop/coding/built-from-source`); per-PWA "open links in Chrome".
- **1Password** app settings can't be restored from backup (checksummed) —
  configure by hand.
- **Raycast**: clipboard history retention → 7 days; custom extensions load
  from their dev source directories.
- **Own apps**: build Synapse macOS app + Receptor from source → /Applications.
- **Nightlight**: the activation script needs a display connected on first run.

## Menu bar: third-party icon order & hiding (manual by design)

Dock order and system/Control Center icon visibility ARE declared
(`hosts/macbook-air.nix` dock block, `modules/macos-defaults.nix`
controlcenter block). Third-party icon order and what iBar hides are not,
and can't sanely be: each icon's spot is an `"NSStatusItem Preferred
Position"` key in that app's own defaults domain holding an absolute pixel
offset from the right screen edge — offsets shift whenever any icon
appears/disappears or the display width changes, macOS rewrites them on
drag, and apps only reread them at launch. "Hidden" isn't a macOS concept
either: an item is hidden iff its offset sits left of iBar's separator.
Machine state, not config — arrange icons and iBar's hide boundary by hand
(⌘-drag). Full research: Notion note "Menu bar / dock in nix — findings"
(2026-08-02).

## Known imperative leftovers (deliberate)

- `com.asmvik.yabai.plist`, `com.alexmiller.geminidesktop.plist`, OpenClaw
  agents — owned by their own projects, not this repo.
- `gh`/`gcloud`/`op` credentials, `~/.claude.json` — runtime auth state, never
  declared.
