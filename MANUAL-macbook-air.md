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

## Menu bar: what's declared vs manual

Declared: dock order (`hosts/macbook-air.nix` dock block), system icon
visibility (ByHost ints in `home/macos-tweaks.nix` menuBarModules — macOS 26
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

- `com.asmvik.yabai.plist`, `com.alexmiller.geminidesktop.plist`, OpenClaw
  agents — owned by their own projects, not this repo.
- `gh`/`gcloud`/`op` credentials, `~/.claude.json` — runtime auth state, never
  declared.
