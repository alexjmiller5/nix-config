# MANUAL-macbook-air.md — MacBook steps nix cannot do

Everything on the laptop that can't be declared, in bootstrap order. (The
mini's equivalent is MANUAL-mac-mini.md.) Sources: blueprint's
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
   otherwise): `for t in alexjmiller5/tap steipete/tap; do brew trust "$t"; done`

## Life background sync: replacement-machine recovery

Nix installs Life, its configuration and the login-time background runner
through `home/common.nix` and Life's Home Manager module. It does **not**
restore the local Keychain entry or the user's sync toggle. A fresh machine
starts with sync off; a normal Nix rebuild preserves an existing toggle.

After completing this manual's machine bootstrap:

1. Sign into 1Password using recovery access that does not depend on either
   old Mac. Retrieve this laptop's Life token from vault
   `a4gdaq4rjdpewl4uppphpjqewm`, item `yaasgo467sp23p77bijckaitrm`, field
   `credential` (`op://a4gdaq4rjdpewl4uppphpjqewm/yaasgo467sp23p77bijckaitrm/credential`).
   This is a dedicated Life-issued device token, separate from the mini's
   token and the AI Agent/admin credential. Its `full` scope permits Life
   data and schema sync, but not token administration. If it has been
   revoked, have a Life administrator issue a replacement and store it in
   this machine's vault; never substitute the admin token.
2. In Terminal on the replacement laptop's desktop, run:

   ```sh
   life background enable --token-stdin
   ```

   Paste the credential at the hidden `Life device token:` prompt and press
   Return. Approve macOS Keychain access if requested. The installed Life
   command stores the runtime copy in Keychain; 1Password holds the recovery
   copy. Routine background sync does not call 1Password or need a 1Password
   service account. Never put the token in a shell command, file, Git or the
   Nix store.
3. Let the background runner initialize and download the replica, then run:

   ```sh
   life background status
   ```

   Verify `enabled: true`, `running: true`, a populated `last_success`,
   `last_error: null` and zero rejected rows in `stats`. `enabled` alone is
   not proof that data synced. Large first downloads take longer. Do not
   start a concurrent `life sync` while the background round is running.
   Check status again after logout/login to verify automatic startup.

If both Macs are lost, recovery uses GitHub for the machine/software config,
1Password for credentials, and the surviving Life hub for synced schema,
tables and history. Edits that never reached the hub need an independent
backup; Nix cannot recover them. This procedure assumes the hub is healthy
and reachable. The mini's equivalent is in
[MANUAL-mac-mini.md](MANUAL-mac-mini.md#life-background-sync-replacement-machine-recovery).

## Machine vaults (1P) — the secret architecture

Each machine has a 1P vault ("MacBook Air" / "Mac Mini") and a read-only
service account (`macbook-air-machine` / `mac-mini-machine`). agenix encrypts
exactly ONE secret per machine — its SA token — and everything else lives in
the machine vault, fetched at runtime with `op read` (by vault/item **ID**,
never name). Adding or rotating a secret = edit the 1P item; the repo and the
machines don't change.

In the vaults today:

* **MacBook Air**: `MacBook Air GitHub PAT nix-config-git` — fine-grained, repos
  `agent-config`/`nix-secrets`/`hammerspoon`, Contents **read/write** (the
  sync agent pushes agent-config). Feeds the git credential helper.
* **Mac Mini**: `Mac Mini GitHub PAT nix-config-git` — same repos, Contents
  **read-only** (the mini is pull-only by design).

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
    'kTCCServiceScreenCapture','kTCCServiceSystemPolicyAllFiles',
    'kTCCServiceCalendar','kTCCServiceAddressBook','kTCCServiceMicrophone')
   ORDER BY service, client;"
```

* **Accessibility**: Hammerspoon, Karabiner-Elements, yabai
  (`/Library/Application Support/yabai/yabai`), AltTab, Raycast,
  BetterDisplay, Ghostty, VS Code, Claude, 1Password, Discord, Zoom
* **Input Monitoring**: Karabiner-Elements (grants land on its helper
  binaries), Dolphin
* **Screen & System Audio Recording** (Screen Recording on older macOS):
  Hammerspoon, AltTab, 1Password, Notion, Claude, Chrome,
  VS Code, Ghostty, Telegram, Zoom, Raycast.
  Enable Hammerspoon for screen capture and restart it if macOS prompts.
* **Full Disk Access**: VS Code, Ghostty, Raycast, Hammerspoon (reads
  Messages chat.db for the paste-OTP hotkey),
  /bin/zsh (launchd/agent shell scripts),
  /Applications/ScreenTimeBackup.app (the weekly Screen Time backup agent —
  grant ONCE after the enabling rebuild; the stable self-signed cert keeps
  the grant valid across rebuilds),
  /Applications/StickerSync.app (the weekly iMessage sticker sync — same
  one-time grant, same stable-cert pattern)
* **Calendar / Contacts**: Raycast
* **Microphone**: Raycast
* **Automation**: Ghostty/Terminal/VS Code → System Events; Hammerspoon; Docker;
  the terminal running `herdr-window` -> Ghostty (allow the first launch
  prompt so its native AppleScript API can open the dedicated window);
  Ghostty → Messages (for `imsg send` — macOS prompts on first send; reads
  need only Ghostty's existing Full Disk Access)

Raycast asks for five at onboarding — Accessibility (window management,
snippet expansion), Files and Folders, Calendar and Contacts, Microphone
(dictation), Screen Recording (screenshots for AI screen awareness). Grant
Full Disk Access instead of the per-folder "Files and Folders" rows; it
supersedes them and is what the search-files extension needs.

Path-keyed clients (brew's versioned node/claude-code paths) re-key on every
version bump and just shed a dead row. Harmless — purge dead rows whenever
auditing.

Purging dead rows: `tccutil reset` does NOT work for uninstalled software
(it errors "No such bundle identifier" once the app leaves LaunchServices)
and can't address path-keyed clients at all. Delete rows directly instead —
same statement against both dbs (user db needs an FDA'd shell, system db
needs sudo), then bounce tccd:

```Shell
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "DELETE FROM access WHERE client IN ('<bundle-id-or-path>', ...); SELECT changes();"
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "DELETE FROM access WHERE client IN ('<bundle-id-or-path>', ...); SELECT changes();"
sudo killall tccd
```

## yabai (Accessibility only — the rest is declared)

The launchd agent is declarative (`modules/yabai.nix`, imported by
`hosts/macbook-air.nix`). The scripting addition is OFF: macOS 26.1's AMFI
enforces library validation on Dock and won't load yabai's third-party ad-hoc
payload, so the SA can't inject regardless of SIP state (verified 2026-08-15).
yabai therefore needs no SIP disable and no `arm64e_preview_abi` boot-arg.

yabai runs from `/Library/Application Support/yabai/yabai` — a copy of the
store binary that activation re-signs with the stable `yabai-signing` cert.
Fixed path + fixed code identity = the Accessibility grant survives every
version bump (nixpkgs' own build is ad-hoc/linker-signed under a hashed store
path, so its grant died on every rebuild and the KeepAlive agent then spammed
Accessibility prompts). The `yabai` CLI on PATH is still the store build; it
only talks to the running server over its socket and needs no grant.

What stays manual (TCC is GUI-only), once:

System Settings > Privacy & Security > Accessibility > `+` > Cmd+Shift+G >
paste `/Library/Application Support/yabai/yabai` > toggle it ON. Remove any
leftover `/nix/store/...-yabai-*/bin/yabai` rows while there.

## SIP status: DISABLED — keep it that way for now

SIP is currently disabled on this machine (originally for yabai; nothing
declared depends on it anymore). **Deliberately kept disabled** since
2026-08-26: macOS ≥26.3 locks the ScreenTimeAgent store (the
DeviceActivity/Cloud segments that carry cross-device per-app AND per-site
Screen Time, incl. iPhone web domains) behind kernel sandbox/TCC enforcement
that even Full Disk Access can't cross — SIP-off plausibly bypasses it.
This 26.1 machine is the only capture point for that data
(screentime-backup agent). Before/after any macOS update past 26.2, verify
the store is still readable:
`ls "$(getconf DARWIN_USER_DIR)com.apple.ScreenTimeAgent/Store/Library/com.apple.DeviceActivity/Cloud"`
If it EPERMs with SIP off, per-site capture is over — reassess then.
(Disabling SIP again after an update re-enables it: the yabai wiki has the
best step-by-step guide —
https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection
— including the Apple-silicon Recovery flow and which csrutil flags to use.
Restoring SIP: `csrutil enable` in Recovery; boot-arg cleanup:
`sudo nvram -d boot-args`.)

## App sign-ins (after first switch; GUI-only, none scriptable)

* **Docker Desktop** - complete its first-run agreement/setup if prompted.
  Approve macOS's administrator prompt if Docker needs to install/update its
  privileged networking helper. This can also recur after Docker upgrades.
  The declared Connect LaunchAgent opens Docker at login; no separate login
  item or Docker account sign-in is needed. Docker must remain running for
  local Connect reads.
* **1Password** — covered in bootstrap step 5 (app sign-in, `op signin`).
* **Claude** — sign into the Claude desktop app and Claude Code (`claude` →
  `/login`); auth state lands in `~/.claude.json` (deliberate leftover).
* **Claude in Chrome** — sign into the browser extension (toolbar icon →
  sign in). Store-installed via the Chrome policy plist, but auth is per-
  profile and GUI-only.
* **1Password in Chrome** — the browser extension (policy-installed and
  pinned) has its own sign-in: click its toolbar icon → unlock; it pairs
  with the desktop app when 1Password → Settings → Browser → "Connect with
  1Password in the browser" is on (then Touch ID unlocks it), otherwise
  sign in with the account password. Per profile, GUI-only.
* **Notion** — sign into the desktop app.
* **VS Code** — sign into GitHub in-app (Copilot etc.). No Settings Sync —
  settings/keybindings are nix-managed.
* **WhatsApp** — pair from the phone (Settings → Linked Devices → QR).
* **Spotify** — sign into the desktop app. `spotify_player` needs nothing:
  its auth lives in 1Password and the wrapper injects it per call (see
  `home/spotify-player.nix` / the `spotify` skill).
* **Google accounts** — System Settings → Internet Accounts: account list,
  addresses, and per-service toggles live in nix-secrets
  `manual/google-accounts.md` (public-repo privacy rule).

## One-time app/setting setup

* **Accessibility → Zoom**: enable scroll-gesture-with-modifier zoom (ctrl) —
  `com.apple.universalaccess` is FDA-gated, not worth automating.
* **Hammerspoon**: console → `hs.ipc.cliInstall("/opt/homebrew")`; preferences →
  hide dock icon.
* **wacli** (WhatsApp linked device for agent group sends; ONE pairing shared
  by both Macs via 1Password): `wacli auth` in a terminal, scan the QR from
  the phone (WhatsApp → Linked devices → Link a device), Ctrl+C once the
  bootstrap sync idles. The wrapper (`op-wrappers.nix`) pushes the session to
  the "AI Agent WhatsApp Linked Device Session" document and pulls it before
  every run, so the mini needs no pairing of its own - just never run wacli
  on both machines at the same moment. If the phone is offline 14 days
  WhatsApp unlinks the device → re-run `wacli auth` anywhere.
* **Chrome**: load-unpacked extensions — Developer mode ON, then Load
  unpacked for each: bypass-paywalls et al from
  `~/Desktop/coding/built-from-source`, and own `chrome-extension`-template
  projects from their repo's `extension/` dir (upcoming:
  bookmark-extension-sync). NOTE the default-deny policy blocks Load-unpacked
  wholesale — loading a new unpacked extension needs the AIRLOCK (lockdown
  flag) in `hosts/macbook-air.nix`, and its path-derived ID needs an
  `allowed` entry to stay alive once re-locked (both documented at the flag).
  Store extensions and PWAs need NO manual steps —
  installed by the Chrome policy plist (`ExtensionSettings` +
  `WebAppInstallForceList`, written to Managed Preferences by
  `modules/chrome-policy.nix` — on switch AND by its root LaunchDaemon at
  every boot, because macOS wipes that directory ~30s after login). ONE
  manual per-PWA setting: chrome →
  app details → "Opening supported links" must stay **Open in Chrome
  browser** (the default) — no policy field exists for it
  (`WebAppSettings`/`WebAppInstallForceList` have none) and the choice lives
  in the profile's `shared_proto_db` LevelDB, so it can't be nix-owned; only
  needs touching if an app prompted and got switched to open-in-app.
  A newly-declared PWA appears only after a full Chrome relaunch (policy is
  read at launch; install lands a minute or two later) - no way to automate,
  so just wait.
* **Chrome UI prefs** — app-owned profile `Preferences`, NO policy exists
  (Chrome rewrites the file constantly, so nix can't own it either) — this
  snapshot IS the declaration (2026-08-13):
  - **Tab position: Vertical**, sidebar collapsed (right-click tab strip →
    Show Tabs Vertically, or Settings → Appearance → Tab strip position).
  - **Toolbar toggles ON** (Customize Chrome → Toolbar): Forward, Downloads,
    Translate, Developer Tools. Pinned toolbar order: Chrome Labs, DevTools,
    Downloads, Translate.
  - **OFF but present** (not removable — no policy for these buttons): Home,
    Open In Split View, New Incognito Window, Bookmarks, Reading List,
    History, Delete Browsing Data, Print, Search with Google Lens, Create QR
    Code, Cast, Reading Mode, Copy Link, Send to your devices, Task Manager.
  - Google Password Manager / Payment Methods / Addresses entries are
    REMOVED outright by the policy plist (`PasswordManagerEnabled` /
    `AutofillCreditCardEnabled` / `AutofillAddressEnabled` = false —
    1Password owns those), so they never appear in this panel.
* **Chrome extension keyboard shortcuts** — app-owned, HMAC-signed in the
  profile's `Secure Preferences` (`extensions.settings.<id>.commands`), so an
  external write is ignored on startup (can't be codified without forging
  Chrome's MAC + super_mac, which risks a protected-prefs reset). An extension
  reload wipes them. Re-bind by hand at `chrome://extensions/shortcuts`:
  - **Tab Copy → Copy selected tabs = ⇧⌘C** ("In Chrome" scope).
* **Tab Copy's custom format** lives in the extension's unprotected LevelDB
  and IS declared, in `home/macbook-air.nix` under `chrome.extensionStorage`.
  Two things keep it from restoring itself, so check both when it goes missing:
  - The module needs the LevelDB lock, so it **skips whenever Chrome is
    running** and only converges on a switch with Chrome quit. Chrome is
    opened at login by its own agent, so quit it first and re-switch.
  - The format id is Tab Copy's own random mint. **Rebuilding the format by
    hand in the UI mints a new id**, which makes the declared id stale — and a
    stale id is destructive, not inert: it overwrites the live format with one
    that no longer exists. After any hand-rebuild, re-dump and update the id.
    Dump it by copying the profile's `Local Extension Settings/<extid>` dir,
    deleting `LOCK`, and reading it with plyvel.
* **1Password** app settings can't be restored from backup (checksummed) —
  configure by hand.
* **Raycast**: clipboard history retention → 7 days; Advanced → Interface Size
  → middle of the three (medium); extensions → see "Raycast extensions"
  section below.
* **Nightlight**: the activation script needs a display connected on first run.

## Raycast extensions (undeclarable — this list IS the declaration)

Raycast registers installed extensions in an encrypted local DB
(`raycast-enc.sqlite`, SQLCipher) with no CLI/API/deeplink to install
headlessly, so extensions can't be nix-managed. Keep this list current when
installing/removing; regenerate it with the "Installed Extensions" store
extension and diff against this section.

Faster restore path: Raycast's own **Export Settings & Data** command writes a
passphrase-encrypted `.rayconfig` covering store extensions, settings, aliases,
hotkeys, snippets, quicklinks and clipboard history — import it on the new Mac
and this list is only the fallback. Scheduling that export (Settings → Advanced
→ Export, pointed at iCloud Drive) needs Raycast Pro; the one-off export is
free.

Store extensions — install via Raycast Store or `https://raycast.com/<slug>`:

`DanielSinclair/base64` · `mooxl/coffee` · `thomas/color-picker` ·
`priithaamer/docker` · `ron-myers/facetime` · `hrishabhn/flighty` ·
`josephschmitt/gif-search` · `bjrmatos/hammerspoon` · `destiner/iconify` ·
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

## Raycast aliases (undeclarable — this list IS the declaration)

Aliases live in the same encrypted DB as extensions — no CLI/deeplink to set
them, so they can't be nix-managed. Set each one manually in Raycast
(Settings → Extensions → select the command → Alias field), or restore them
wholesale via `.rayconfig` import. Keep this list current when adding/removing
one. To regenerate: Export Settings & Data (any password), then the RAYCFG3
export is AES-256-GCM with an scrypt(N=16384) key — read `settings.commands[]`,
each `alias` maps to its command `id`.

**App launchers:**

| Alias | Opens | Alias | Opens |
|---|---|---|---|
| `find` | FindMy | `nc` | Notion Calendar |
| `gem` | Gemini | `passwords` | 1Password |
| `gmaps` | Google Maps | `sptfy` | Spotify |
| `gpt` | ChatGPT | `ss` | Screenshot |
| `in` | LinkedIn | `sys` | System Settings |
| `insta` | Instagram | `terminal` | Ghostty |
| `messanger` | Messenger | `vscode` | Visual Studio Code |
| `msgs` | Messages | `yt` | YouTube |
| | | `zoom` | zoom.us |

**Quicklinks:**

| Alias | Target |
|---|---|
| `apps` | `/Applications` |
| `desk` | `~/Desktop` |
| `docs` | `~/Documents` |
| `down` | `~/Downloads` |
| `sg` | `https://google.com/search?q={Query}` (Search Google) |
| `tasks` | Notion Tasks DB (notion:// deep link) |

**Apple Shortcuts:** `qn` and `task` (run shortcuts by UUID — set from the
Apple Shortcuts extension's command list).

**Extension commands** (extension → command):

| Alias | Extension → command |
|---|---|
| `blue` | toothpick → manage-bluetooth-connections |
| `calc` | calculator → history |
| `cam` | raycast-core → open camera |
| `ch` | clipboard-history → history |
| `f` | file-search → search files |
| `lr` | git-repos → list |
| `pp` | spotify-player → toggle play/pause |
| `sc` | contacts → search |
| `sd` | spotify-player → devices |
| `ses` | emoji-picker → search emoji |
| `sm` | zoom → start meeting |
| `sod` | audio-device → set output device |
| `sw` | navigation → switch windows |
| `tmb` | toggle-menu-bar → toggle |
| `yl` | spotify-player → your library |

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

## Notifications: what's declared vs manual

Declared, `home/macos/notification-prefs.nix` + the block in
`home/macbook-air.nix`: per-app "Allow notifications" (`enable`), plus alert
style / venues / badge / sound / summarize (`flags`), Show previews
(`content_visibility`) and Notification grouping (`grouping`). Re-capture with
`scripts/capture-notification-prefs` after changing anything in the UI —
uninstalled apps drop out on every capture, so the list stays honest.

The live store is usernoted's group container, NOT
`~/Library/Preferences/com.apple.ncprefs.plist`. That path looks like the
right one and is what every guide online names, but on this machine it is a
stale copy: it still listed apps uninstalled months ago, was missing every
recently-installed one, and writes to it changed nothing in the UI.

`enable` maps onto two `flags` bits rather than a field of its own: an app is
allowed iff bit 23 is clear OR bit 25 is set (bit 23 records that a choice was
made, bit 25 carries allow/deny). Verified 2026-09-01 end to end by flipping
one app in nix and watching System Settings switch it from Off to on.

**Quit System Settings to SEE a switch's changes.** It caches the app list at
launch and never notices an external write, so switching with it open leaves
the Notifications pane showing the old values — quit and reopen it (navigating
away and back is not enough). This is display-only: the write itself lands and
survives, and System Settings does not clobber it on quit, so there is no need
to quit *before* switching. Same for checking state from the shell, which
always reads live: `scripts/capture-notification-prefs | grep -A1 '"<bundle>"'`.

Manual: the OS's own notification sources (Wi-Fi, Bluetooth, Software Update,
tccd — the `_SYSTEM_CENTER_:` entries and the bundles under
`/System/Library/UserNotifications/`) are deliberately left undeclared; their
values churn with OS updates.

## Known imperative leftovers (deliberate)

* `gcloud`/`op` credentials, `~/.claude.json` — runtime auth state, never
  declared. git's GitHub auth is NOT in this list anymore: it's the agenix PAT.
