{
  config,
  pkgs,
  lib,
  username,
  ...
}:

# MacBook Air — the GUI-full host. The mini matches it at the shell/dev
# level (see home/dev-tools.nix + home/mac-mini.nix); this host adds the GUI
# layer (casks, dock, Chrome policy) and the Apple build chain, and
# lacks the mini's headless-server bits (never-sleep power, headless
# tailscaled, callhistory backup). Home profile: home/macbook-air.nix.
# Shared base (stateVersion, unfree predicate, /etc/nix-darwin, brew zap, …)
# comes from modules/darwin-base.nix via mkHost.
{
  imports = [
    ../modules/notunes.nix
    ./macbook-air-chrome-policy.nix
  ];

  # Human steps nix cannot do render into MANUAL-macbook-air.md (modules/manual.nix).
  manual.host = "macbook-air";
  manual.docs = [
    "docs/machine-vaults.md"
    "docs/sip.md"
    "docs/tcc.md"
    "docs/notifications.md"
    "docs/op-connect.md"
  ];

  # The laptop's ONE agenix secret: the macbook-air-machine 1P service-account
  # token (read-only on the "MacBook Air" vault). Every other secret lives in
  # that vault, fetched at runtime via op read — see secrets/secrets.nix.
  age.secrets.machine-sa = {
    file = ../secrets/machine-sa-laptop.age;
    owner = username;
  };

  # The laptop has a normal pre-existing /opt/homebrew; let nix-homebrew
  # adopt it on first activation instead of erroring.
  nix-homebrew.autoMigrate = true;

  # Tailscale runs via the GUI app (tailscale-app cask below), unlike the
  # mini's headless tailscaled.

  # Screen Time backup ALSO on the laptop (mini keeps running its own): only a
  # macOS ≤26.2 machine can read the ScreenTimeAgent store, and its
  # DeviceActivity/Cloud segments carry the cross-device per-app AND per-site
  # usage (incl. iPhone web domains) that the mini (26.3, vaulted) cannot
  # capture. dirSuffix keeps same-day runs from colliding in the shared
  # iCloud folder. One manual step after first rebuild: grant
  # /Applications/ScreenTimeBackup.app Full Disk Access (MANUAL-macbook-air.md).
  services.screentime-backup = {
    enable = true;
    user = username;
    dirSuffix = "-macbook";
  };

  # iMessage sticker sync: MacBook only (the mini has no Messages sign-in).
  # Weekly copy of the sticker drawer + chat sticker attachments into
  # ~/Documents/ios-stickers/synced. One manual step after first rebuild:
  # grant /Applications/StickerSync.app Full Disk Access (MANUAL-macbook-air.md).
  services.sticker-sync = {
    enable = true;
    user = username;
  };

  # Disable auto display brightness (laptop-only; written to /Library/Preferences
  # as root — takes effect after a restart).
  system.defaults.CustomSystemPreferences = {
    "/Library/Preferences/com.apple.iokit.AmbientLightSensor" = {
      "Automatic Display Enabled" = false;
    };
  };

  system.activationScripts.preActivation.text = ''
    # Package removal needs root; Homebrew's user activation cannot prompt for
    # sudo. Stop the remaining registered helpers before package cleanup.
    keyboardUser=$(/usr/bin/id -u ${lib.escapeShellArg username})
    for service in \
      system/org.pqrs.service.daemon.Karabiner-Core-Service \
      system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon \
      "gui/$keyboardUser/org.pqrs.service.agent.Karabiner-Core-Service-rev2" \
      "gui/$keyboardUser/org.pqrs.service.agent.Karabiner-Console-User-Server"; do
      if /bin/launchctl print "$service" >/dev/null 2>&1; then
        /bin/launchctl bootout "$service"
      fi
    done
    if [ -x '/Library/Application Support/org.pqrs/Karabiner-Elements/uninstall.sh' ]; then
      /bin/bash '/Library/Application Support/org.pqrs/Karabiner-Elements/uninstall.sh'
    fi
    for receipt in org.pqrs.Karabiner-Elements org.pqrs.Karabiner-DriverKit-VirtualHIDDevice; do
      if /usr/sbin/pkgutil --pkg-info "$receipt" >/dev/null 2>&1; then
        /usr/sbin/pkgutil --forget "$receipt"
      fi
    done
    # Retain leftover runtime state in a private temporary backup; leaving it
    # under Application Support would make Homebrew request sudo again.
    if [ -d '/Library/Application Support/org.pqrs/tmp' ]; then
      keyboardBackup=$(/usr/bin/mktemp -d /private/tmp/karabiner-uninstall.XXXXXX)
      /bin/mv '/Library/Application Support/org.pqrs/tmp' "$keyboardBackup/"
      /bin/rmdir '/Library/Application Support/org.pqrs' 2>/dev/null || true
    fi
  '';

  # Laptop-only root activation steps. Other modules append their own entries.
  system.activationScripts.postActivation.text = ''
    # Window controls use Hammerspoon; remove the separately installed binary
    # and its dedicated signing identity along with the undeclared service.
    /bin/rm -f '/Library/Application Support/yabai/yabai'
    /bin/rmdir '/Library/Application Support/yabai' 2>/dev/null || true
    if /usr/bin/security find-certificate -c yabai-signing /Library/Keychains/System.keychain >/dev/null 2>&1; then
      /usr/bin/security delete-identity -c yabai-signing /Library/Keychains/System.keychain
    fi

    # Rosetta 2, declared (needed by EGGNOGG+ in home/macbook-air.nix —
    # x86_64-only). No nix-darwin option exists; activation runs as root,
    # so install here, guarded by the oahd check to stay idempotent.
    if ! /usr/bin/pgrep -q oahd; then
      /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    fi
  '';

  # Dock contents, in order (snapshotted 2026-08-02). The list IS the dock:
  # nix rewrites it on switch, so manual drag-ins don't survive.
  system.defaults.dock.persistent-apps = [
    { app = "/Applications/Spotify.app"; }
    { app = "/System/Applications/Messages.app"; }
    { app = "/Applications/WhatsApp.app"; }
    { app = "/System/Applications/Mail.app"; }
    { app = "/Applications/Ghostty.app"; }
    { app = "/Applications/Visual Studio Code.app"; }
    { app = "/Applications/Google Chrome.app"; }
    { app = "/Applications/Notion Calendar.app"; }
    { app = "/Applications/Notion.app"; }
    { app = "/Applications/Claude.app"; }
    { app = "/Users/${username}/Applications/Chrome Apps.localized/Google Maps.app"; }
    { app = "/System/Applications/Utilities/Screen Sharing.app"; }
  ];

  # Brew-ONLY leftovers — everything available in nixpkgs migrated to
  # home/macbook-air.nix home.packages on 2026-08-10 (dep cruft and the
  # unused ruby managers dropped outright; brew auto-keeps real deps).
  homebrew = {
    # trusted = true feeds Homebrew's tap-trust store at activation — without
    # it brew ignores the tap's formulae/casks entirely.
    taps = [
      # Alex's personal cask tap — apps released by their repos' CI
      # (receptor, ...).
      {
        name = "alexjmiller5/tap";
        trusted = true;
      }
      {
        name = "steipete/tap";
        trusted = true;
      }
    ];
    brews = [
      # Not in nixpkgs (checked 2026-09-01); skills + nightlight migrated out.
      "chrome-cli"
      # iMessage CLI for agents (read chat.db, send via Messages.app) — not in
      # nixpkgs. Needs TCC grants, see MANUAL-macbook-air.md.
      "steipete/tap/imsg"
    ];
    casks = [
      "1password"
      # op comes from pkgs._1password-cli (ai-agent.nix) — the desktop app
      # accepts the nix-built binary (Touch ID verified 2026-08-26).
      "alt-tab"
      "betterdisplay"
      "binary-ninja-free"
      "burp-suite"
      "chatgpt"
      "claude"
      # @latest tracks releases faster than the plain cask; fable-5-1 needs >= 2.1.251
      "claude-code@latest"
      # nixpkgs lags upstream by several releases; see home/codex.nix.
      "codex"
      "codexbar"
      "discord"
      "docker-desktop"
      "dolphin"
      "ghostty"
      "google-chrome"
      "hammerspoon"
      "libreoffice"
      "mactex-no-gui"
      "notion"
      "notion-calendar"
      "notion-cli"
      # notunes comes from modules/notunes.nix
      "pearcleaner"
      "processing"
      "raycast"
      # From alexjmiller5/tap — released + notarized by receptor's CI.
      # Replaces the DerivedData rm-cp-codesign flow. Fully qualified to
      # avoid any future homebrew/cask collision.
      "alexjmiller5/tap/receptor"
      # From alexjmiller5/tap — Offline Shazam's Mac app, released by its CI.
      "alexjmiller5/tap/offline-shazam"
      "repobar"
      "slack"
      "spotify"
      "tailscale-app"
      "visual-studio-code"
      "whatsapp"
      "wireshark-app"
      "zoom"
    ];
    # App Store apps (enumerated via `mas list`, 2026-07-28). Requires being
    # signed in to the App Store; mas can't install un-purchased apps.
    # NOTE: cleanup = "zap" does NOT uninstall masApps (brew bundle skips App
    # Store apps; mas has no uninstall). Removing one = delete its line here
    # AND rm the .app manually.
    masApps = {
      "Flappy Golf 2" = 1154174205;
      "Flighty" = 1358823008;
      "Octagon" = 691956219;
      "Telegram" = 747648890;
      "Xcode" = 497799835;
    };

    # No caskArgs.no_quarantine: Homebrew 6's brew bundle passes it malformed
    # (--no_quarantine, fails every new cask install) and the flag is removed
    # upstream on 2026-09-01. New casks get the one-time Gatekeeper prompt.
  };

  # Human steps nix cannot do (rendered into MANUAL-<host>.md; verified by manual-check).
  manual.steps = {
    docker-first-run = {
      title = "Docker Desktop first run";
      owner = "docker-desktop";
      desktop = true;
      body = ''
        Complete its first-run agreement/setup if prompted.
        Approve macOS's administrator prompt if Docker needs to install/update its
        privileged networking helper. This can also recur after Docker upgrades.
        The declared Connect LaunchAgent opens Docker at login; no separate login
        item or Docker account sign-in is needed. Docker must remain running for
        local Connect reads.
      '';
    };
    codex-login = {
      title = "Sign into Codex";
      owner = "codex";
      body = ''
        `codex login` (the ChatGPT-subscription seat). Its auth lives in the login Keychain
        (`cli_auth_credentials_store = "keyring"`); neither the operator token nor a Nix rebuild recreates it.
      '';
      verify = "codex login status";
    };
    claude-in-chrome-login = {
      title = "Sign into Claude in Chrome";
      owner = "claude-in-chrome";
      desktop = true;
      body = ''
        Sign into the browser extension (toolbar icon →
        sign in). Store-installed via the Chrome policy plist, but auth is per-
        profile and GUI-only.
      '';
    };
    onepassword-in-chrome = {
      title = "Sign into 1Password in Chrome";
      owner = "1password";
      desktop = true;
      body = ''
        The browser extension (policy-installed and
        pinned) has its own sign-in: click its toolbar icon → unlock; it pairs
        with the desktop app when 1Password → Settings → Browser → "Connect with
        1Password in the browser" is on (then Touch ID unlocks it), otherwise
        sign in with the account password. Per profile, GUI-only.
      '';
    };
    notion-login = {
      title = "Sign into Notion";
      owner = "notion";
      desktop = true;
      body = ''
        Sign into the desktop app.
      '';
    };
    vscode-login = {
      title = "Sign into VS Code";
      owner = "visual-studio-code";
      desktop = true;
      body = ''
        Sign into GitHub in-app (Copilot etc.). No Settings Sync -
        settings/keybindings are nix-managed.
      '';
    };
    whatsapp-pair = {
      title = "Pair WhatsApp";
      owner = "whatsapp";
      desktop = true;
      body = ''
        Pair from the phone (Settings → Linked Devices → QR).
      '';
    };
    spotify-login = {
      title = "Sign into Spotify";
      owner = "spotify";
      desktop = true;
      body = ''
        Sign into the desktop app. `spotify_player` needs nothing:
        its auth lives in 1Password and the wrapper injects it per call (see
        `home/spotify-player.nix` / the `spotify` skill).
      '';
    };
    google-accounts = {
      title = "Google accounts in System Settings";
      owner = "macos-defaults";
      desktop = true;
      body = ''
        System Settings → Internet Accounts: account list,
        addresses, and per-service toggles live in nix-secrets
        `manual/google-accounts.md` (public-repo privacy rule).
      '';
    };
    accessibility-zoom = {
      title = "Accessibility → Zoom";
      owner = "macos-defaults";
      desktop = true;
      body = ''
        Enable scroll-gesture-with-modifier zoom (ctrl) -
        `com.apple.universalaccess` is FDA-gated, not worth automating.
      '';
    };
    hammerspoon-ipc = {
      title = "Hammerspoon CLI + dock icon";
      owner = "hammerspoon";
      desktop = true;
      body = ''
        Console → `hs.ipc.cliInstall("/opt/homebrew")`; preferences →
        hide dock icon.
      '';
      verify = "test -x /opt/homebrew/bin/hs";
    };
    chrome-load-unpacked = {
      title = "Chrome load-unpacked extensions and PWAs";
      owner = "chrome-policy";
      desktop = true;
      body = ''
        Load-unpacked extensions - Developer mode ON, then Load
        unpacked for each: bypass-paywalls et al from
        `~/Desktop/coding/built-from-source`, and own `chrome-extension`-template
        projects from their repo's `extension/` dir (upcoming:
        bookmark-extension-sync). NOTE the default-deny policy blocks Load-unpacked
        wholesale - loading a new unpacked extension needs the AIRLOCK (lockdown
        flag) in `hosts/macbook-air.nix`, and its path-derived ID needs an
        `allowed` entry to stay alive once re-locked (both documented at the flag).
        Store extensions and PWAs need NO manual steps -
        installed by the Chrome policy plist (`ExtensionSettings` +
        `WebAppInstallForceList`, written to Managed Preferences by
        `modules/chrome-policy.nix` - on switch AND by its root LaunchDaemon at
        every boot, because macOS wipes that directory ~30s after login). ONE
        manual per-PWA setting: chrome →
        app details → "Opening supported links" must stay **Open in Chrome
        browser** (the default) - no policy field exists for it
        (`WebAppSettings`/`WebAppInstallForceList` have none) and the choice lives
        in the profile's `shared_proto_db` LevelDB, so it can't be nix-owned; only
        needs touching if an app prompted and got switched to open-in-app.
        A newly-declared PWA appears only after a full Chrome relaunch (policy is
        read at launch; install lands a minute or two later) - no way to automate,
        so just wait.
      '';
    };
    claude-in-chrome-site-grants = {
      title = "Claude in Chrome per-site grants";
      owner = "claude-in-chrome";
      desktop = true;
      body = ''
        Its "Always allow actions on this site" grants live in the same LevelDB as
        Tab Copy's format (same reason it cannot be declared), so allow sites by clicking the
        extension's own popup once per site.
      '';
    };
    onepassword-settings = {
      title = "1Password app settings";
      owner = "1password";
      desktop = true;
      body = ''
        App settings can't be restored from backup (checksummed) - configure by hand.
      '';
    };
    raycast-settings = {
      title = "Raycast settings";
      owner = "raycast";
      desktop = true;
      body = ''
        Clipboard history retention → 7 days; Advanced → Interface Size
        → middle of the three (medium); extensions → see "Raycast extensions"
        section below.
      '';
    };
    screentime-backup-fda = {
      title = "ScreenTimeBackup.app Full Disk Access";
      owner = "screentime-backup";
      desktop = true;
      body = ''
        System Settings → Privacy & Security → **Full Disk Access** → [+] → `/Applications/ScreenTimeBackup.app`, toggle on.
        The app is re-signed with the same stable cert every rebuild, so the grant persists. Kick it once:
        `launchctl kickstart -k gui/$(id -u)/com.alexmiller.screentime-backup`, then check `~/Library/Logs/screentime-backup.log` for a success line
        (a `cannot read` line means the grant is missing).
      '';
      verify = "grep -q 'backup OK' ~/Library/Logs/screentime-backup.log";
    };
    sticker-sync-fda = {
      title = "StickerSync.app Full Disk Access";
      owner = "sticker-sync";
      desktop = true;
      body = ''
        System Settings → Privacy & Security → **Full Disk Access** → [+] → `/Applications/StickerSync.app`, toggle on.
        The app is re-signed with the same stable cert every rebuild, so the grant persists. Kick it once:
        `launchctl kickstart -k gui/$(id -u)/com.alexmiller.sticker-sync`, then check `~/Library/Application Support/sticker-sync/launchd.log` for a success line
        (a `cannot read` line means the grant is missing).
      '';
      verify = "grep -q 'sticker sync done' \"$HOME/Library/Application Support/sticker-sync/launchd.log\"";
    };
    sip-disabled = {
      title = "SIP stays disabled; verify the Screen Time store after updates";
      owner = "screentime-backup";
      body = ''
        SIP is deliberately disabled on this machine - rationale, the update caveat and how to disable it again
        after a macOS update are in docs/sip.md. After any macOS update past 26.2 verify the Screen Time store is
        still readable (the verify below); an EPERM means per-site capture is over - reassess then.
      '';
      verify = "ls \"$(getconf DARWIN_USER_DIR)com.apple.ScreenTimeAgent/Store/Library/com.apple.DeviceActivity/Cloud\" >/dev/null";
    };
    tcc-grants = {
      title = "TCC grants";
      owner = "tcc";
      phase = "snapshot";
      desktop = true;
      verify = "capture-snapshot tcc --diff ${../snapshots/macbook-air/tcc.txt}";
      body = ''
        System Settings → Privacy & Security. The committed capture is
        `snapshots/macbook-air/tcc.txt` (`capture-snapshot tcc`; refresh with
        `just snapshot tcc`); audit and purge per docs/tcc.md.

        Raycast asks for five at onboarding - Accessibility (window management,
        snippet expansion), Files and Folders, Calendar and Contacts, Microphone
        (dictation), Screen Recording (screenshots for AI screen awareness). Grant
        Full Disk Access instead of the per-folder "Files and Folders" rows; it
        supersedes them and is what the search-files extension needs.
      '';
    };
    chrome-ui-prefs = {
      title = "Chrome UI prefs";
      owner = "chrome";
      phase = "snapshot";
      desktop = true;
      verify = "capture-snapshot chrome-ui --diff ${../snapshots/macbook-air/chrome-ui.txt}";
      body = ''
        Live capture: `capture-snapshot chrome-ui` (tab strip, toolbar pins, extension
        shortcuts) vs `snapshots/macbook-air/chrome-ui.txt`; refresh with `just snapshot chrome-ui`.
        App-owned profile `Preferences`, NO policy exists
        (Chrome rewrites the file constantly, so nix can't own it either) - this
        snapshot IS the declaration (2026-08-13):
        - **Tab position: Vertical**, sidebar collapsed (right-click tab strip →
          Show Tabs Vertically, or Settings → Appearance → Tab strip position).
        - **Toolbar toggles ON** (Customize Chrome → Toolbar): Forward, Downloads,
          Translate, Developer Tools. Pinned toolbar order: Chrome Labs, DevTools,
          Downloads, Translate.
        - **OFF but present** (not removable - no policy for these buttons): Home,
          Open In Split View, New Incognito Window, Bookmarks, Reading List,
          History, Delete Browsing Data, Print, Search with Google Lens, Create QR
          Code, Cast, Reading Mode, Copy Link, Send to your devices, Task Manager.
        - Google Password Manager / Payment Methods / Addresses entries are
          REMOVED outright by the policy plist (`PasswordManagerEnabled` /
          `AutofillCreditCardEnabled` / `AutofillAddressEnabled` = false -
          1Password owns those), so they never appear in this panel.
      '';
    };
    chrome-extension-shortcuts = {
      title = "Chrome extension keyboard shortcuts";
      owner = "chrome";
      phase = "snapshot";
      desktop = true;
      verify = "capture-snapshot chrome-ui --diff ${../snapshots/macbook-air/chrome-ui.txt}";
      body = ''
        App-owned, HMAC-signed in the
        profile's `Secure Preferences` (`extensions.settings.<id>.commands`), so an
        external write is ignored on startup (can't be codified without forging
        Chrome's MAC + super_mac, which risks a protected-prefs reset). An extension
        reload wipes them. Re-bind by hand at `chrome://extensions/shortcuts`:
        - **Tab Copy → Copy selected tabs = ⇧⌘C** ("In Chrome" scope).
      '';
    };
    tab-copy-format = {
      title = "Tab Copy custom copy format";
      owner = "chrome";
      phase = "snapshot";
      desktop = true;
      body = ''
        Lives in the extension's
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
        recreated, which is the reason this is not declared - any pinned id goes
        stale the first time the format is rebuilt.
      '';
    };
    raycast-extensions = {
      title = "Raycast extensions";
      owner = "raycast";
      phase = "snapshot";
      desktop = true;
      body = ''
        Raycast registers installed extensions in an encrypted local DB
        (`raycast-enc.sqlite`, SQLCipher) with no CLI/API/deeplink to install
        headlessly, so extensions can't be nix-managed. Keep this list current when
        installing/removing; regenerate it with the "Installed Extensions" store
        extension and diff against this section.

        Faster restore path: Raycast's own **Export Settings & Data** command writes a
        passphrase-encrypted `.rayconfig` covering store extensions, settings, aliases,
        hotkeys, snippets, quicklinks and clipboard history - import it on the new Mac
        and this list is only the fallback. Scheduling that export (Settings → Advanced
        → Export, pointed at iCloud Drive) needs Raycast Pro; the one-off export is
        free.

        Store extensions - install via Raycast Store or `https://raycast.com/<slug>`:

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

        * Git Repos - `~/Desktop/coding/active-projects/raycast-git-repos`
          (github.com/alexjmiller5/raycast-git-repos)
        * Messages - `~/Desktop/coding/active-projects/raycast-messages`
          (github.com/alexjmiller5/raycast-messages)

        Restore: install each store extension from the Store; for the two custom
        ones run `npm ci && npx ray develop` in each dir, then Ctrl-C once loaded
        (the dev import persists without the watcher).
      '';
    };
    raycast-aliases = {
      title = "Raycast aliases";
      owner = "raycast";
      phase = "snapshot";
      desktop = true;
      body = ''
        Aliases live in the same encrypted DB as extensions - no CLI/deeplink to set
        them, so they can't be nix-managed. Set each one manually in Raycast
        (Settings → Extensions → select the command → Alias field), or restore them
        wholesale via `.rayconfig` import. Keep this list current when adding/removing
        one. To regenerate: Export Settings & Data (any password), then the RAYCFG3
        export is AES-256-GCM with an scrypt(N=16384) key - read `settings.commands[]`,
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

        **Apple Shortcuts:** `qn` and `task` (run shortcuts by UUID - set from the
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
      '';
    };
  };

}
