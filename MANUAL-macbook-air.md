# MANUAL-macbook-air.md - MacBook steps nix cannot do

Everything on the laptop that requires native setup, in bootstrap order.
The mini's equivalent is MANUAL-mac-mini.md.

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
   the "MacBook Air" vault). Agent operator credentials have their own
   enrollment below; this machine token does not supply them:
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
   Activation decrypts the bootstrap token onto the agenix RAM disk and
   installs `bootstrap-companion-repos`. `/etc/nix-darwin` links to the clone;
   the `switch-laptop` alias works from anywhere. Activation never reads the
   machine vault or clones companions.
5. Sign into the 1Password app (installed by the switch); `op signin`. There
   is no `gh auth login` or `op plugin` setup: ongoing Git auth uses the
   operator `gh` PATH wrapper.
6. Home Manager creates plugin links inside `~/.config/agent-config` before
   the first clone. If this directory has no `.git`, preserve it elsewhere
   first (choose an unused backup destination):
   ```Shell
   mv ~/.config/agent-config ~/.config/agent-config.bootstrap-links
   ```
   Then run the explicit initial clone command as the user in that terminal:
   ```Shell
   bootstrap-companion-repos
   ```
   It skips existing clones and refuses non-repository directories without
   reading credentials. Only missing repos in `patRepos` get a
   machine-vault helper passed to that single `git clone` command; nothing
   is saved in Git config. Other clones, including hammerspoon, use normal
   Git auth. Failure stops the command; correct bootstrap access and rerun
   it to finish initial setup. Run `switch-laptop` again to restore declared
   plugin links into the clone; the out-of-store symlinks then resolve.
   Later switches never retry bootstrap. To recover a deleted clone on an
   enrolled machine, use ordinary `git clone` with operator auth.
   Enroll the independent AI Agent token below for unattended repo sync.
7. Commit + push the step-3 changes (secrets.nix + the recreated .age) — push
   auth works now.
8. Trust the third-party taps (brew's tap-trust gate blocks formula loads
   otherwise): `for t in alexjmiller5/tap steipete/tap; do brew trust "$t"; done`

## Agent operator credentials: enrollment and rotation

Agent tools use the independently provisioned AI Agent credential in the
existing `~/.local/state/op/agent-sa-token` file (raw token only, owned by
the local user, mode `0600`). Preserve it on an enrolled machine. Nix installs
the initializer and consumers; it neither creates nor refreshes this file.
Agent SSH, local Connect and launchd companion-repo sync consume it through
their existing interfaces. No machine service account supplies or refreshes
the agent token.

For a replacement machine or deliberate rotation, use native 1Password
desktop authentication to retrieve the authoritative AI Agent credential:
vault `4eeyrkqibibn7k4j6rz2fbzvxm`, item `bktt2mfgbrbry53jrvitgxq45q`.
The credential owner enrolls that token into the existing file with private
permissions, using hidden input rather than a shell-history literal. This
is separate from Nix bootstrap; do not recover from a machine-vault copy or
substitute a machine SA. No additional credential cache is needed. After
rotation, restart agent sessions and follow [Connect recovery](docs/op-connect.md).

Claude Code and Codex subscription sign-ins are separate native logins
(`claude` -> `/login`, `codex login`). Preserve their app-owned auth state;
neither the operator token nor a Nix rebuild recreates it.

## Life background sync: replacement-machine recovery

Nix installs Life, its configuration and the login-time background runner
through `home/common.nix` and Life's Home Manager module. It does **not**
restore the local Keychain entry or the user's sync toggle. A fresh machine
starts with sync off; a normal Nix rebuild preserves an existing toggle.

After completing this manual's machine bootstrap, sign the Mac into Life from
its logged-in desktop Terminal:

```sh
life login --name "MacBook Air"
```

The command opens the Life browser sign-in flow. Complete the email one-time
code challenge and approve the displayed device. Life stores the scoped device
credential in macOS Keychain. This login does not enable background sync.

Then opt into background sync explicitly:

```sh
life background enable
```

If the browser did not open automatically, copy the URL printed by `life login`
into the signed-in browser. Run enrollment and the enable command in a Terminal
attached to the logged-in desktop so macOS can authorize Keychain access. Do
not recover or copy a Life token through a machine vault, a service account, a
shell literal, a file, Git or the Nix store.

1. Let the background runner initialize and download the replica, then run:

   ```sh
   life background status
   ```

   Verify `enabled: true`, `running: true`, a populated `last_success`,
   `last_error: null` and zero rejected rows in `stats`. `enabled` alone is
   not proof that data synced. Large first downloads take longer. Do not
   start a concurrent `life sync` while the background round is running.
   Check status again after logout/login to verify automatic startup.

If both Macs are lost, install Nix from GitHub and enroll each replacement
through the Life browser sign-in flow. The surviving Life hub supplies synced
schema, tables and history. Edits that never reached the hub need an
independent backup; Nix cannot recover them. This procedure assumes the hub is
healthy and reachable. The mini's equivalent is in
[MANUAL-mac-mini.md](MANUAL-mac-mini.md#life-background-sync-replacement-machine-recovery).

## Machine vaults (1P) — the secret architecture

Each machine has a 1P vault ("MacBook Air" / "Mac Mini") and a read-only
service account (`macbook-air-machine` / `mac-mini-machine`). agenix encrypts
exactly ONE secret per machine - its bootstrap SA token. Machine vaults are
for initial Nix bootstrap; agent operator credentials use the independent
enrollment above. Each host's `machineVaultGit.patOpRef` identifies its
fine-grained bootstrap GitHub PAT. `patRepos` limits the helper to initial
clones of the listed repositories; it must stay within the PAT's grants.
Cloning needs Contents read access only, regardless of any broader existing
PAT grant. No routine pull or push uses these PATs. Both hosts' launchd repo
sync jobs use the operator `gh` helper with the independently enrolled AI
Agent token; they do not read or refresh machine-vault credentials.

PATs are minted by hand (GitHub has no token-creation API): github.com →
Settings → Developer settings → Fine-grained tokens; they cap at 1-year
expiry, so ensure the bootstrap PAT is valid before setting up a replacement
machine. Its expiry does not affect daily repo sync. Machine lost = revoke
that machine's SA (1P dashboard), drop its
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

* **Accessibility**: Hammerspoon, Karabiner-Elements, AltTab, Raycast,
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

## Window controls

Hammerspoon owns manual placement, resize, and native Space navigation. Its
Accessibility grant covers these controls; no separate window manager or
scripting addition is required. The exported `homeModules.macos-window-management`
module declares native Control-Left/Right desktop navigation. The laptop imports
it; the headless mini does not need interactive desktop shortcuts.

## SIP status: DISABLED — keep it that way for now

SIP is currently disabled on this machine. **Deliberately kept disabled** since
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
* **Tab Copy's custom copy format** — lives in the extension's
  `chrome.storage.local` (an on-disk LevelDB Chrome keeps exclusively locked
  while it runs), so it cannot be written from an activation script on a
  machine where Chrome is opened at login. Recreate it by hand in Tab Copy's
  options → Formats, and leave the other fields empty:

  | Field | Value |
  |---|---|
  | Name | `Default` |
  | Tab | `[url]` |
  | Tab delimiter | `[n]` |
  | Window delimiter | `[n]` |
  | Start, End, Window start, Window end | *(empty)* |

  Net effect: copies the selected tabs' URLs, one per line, nothing else.
  Tab Copy mints a fresh random id (`custom-xxxxxx`) each time it is
  recreated, which is the reason this is not declared — any pinned id goes
  stale the first time the format is rebuilt.
* **Claude in Chrome's per-site grants** ("Always allow actions on this
  site") — same LevelDB, same reason, so allow sites by clicking the
  extension's own popup once per site.
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

## Finder preferences and sidebar

`home/macos/finder.nix` declares full paths, list view, large list icons,
folder-size calculation, filename extensions, search scope, sorting, desktop
disk visibility, new-window target, tabs, trash options, and Recent Tags.
The laptop enables `macos.finder.desktop.enable`; the mini keeps the shared
baseline. Activation does not restart Finder. Existing folder view choices
in `.DS_Store` can override global defaults; use Finder's View Options for
intentional per-folder changes.

Set the remaining Sidebar selections in Finder Settings on a replacement Mac:

- Favorites: Applications, Desktop, Documents, and Downloads enabled.
- Locations: External disks and CDs/DVDs/iOS Devices enabled.
- Disable the other pictured entries: Recents, Shared, Movies, Music,
  Pictures, iCloud Drive, Cloud Storage, home folder, On My Mac, the computer,
  Hard disks, AirDrop, Bonjour computers, Connected servers, and Trash.

Modern Finder stores these selections in shared-file-list archives containing
machine-bound bookmarks. The available CLI and supported management APIs do
not expose the complete checkbox set; do not copy those archives or write
the obsolete `com.apple.sidebarlists` domain.

iCloud sign-in and Desktop/Documents syncing use the native Apple Account
interface. Nix does not enroll an account or restore its session.
