{
  config,
  pkgs,
  username,
  inputs,
  ...
}:

# Shared base (stateVersion, unfree predicate, /etc/nix-darwin, brew zap, …)
# comes from modules/darwin-base.nix via mkHost.
{
  # Human steps nix cannot do render into MANUAL-mac-mini.md (modules/manual.nix).
  manual.host = "mac-mini";
  manual.docs = [
    "docs/machine-vaults.md"
    "docs/tcc.md"
    "docs/op-auth.md"
  ];

  # Headless box: never sleep, come back after power loss.
  power.sleep.computer = "never";
  power.sleep.display = "never";
  power.restartAfterPowerFailure = true;

  # Apple build host for agents: Xcode 27 (App Store), Apple's headless MCP
  # server, simulators. The laptop stays on Xcode 26.3 until its macOS passes
  # 26.2 (Screen Time backup hold), so it does not enable this yet.
  services.xcode-agent = {
    enable = true;
    user = username;
    allowedFolders = [ "/Users/${username}/Desktop/coding" ];
    # `codesign -dv <binary>` prints both values.
    approvedAgents = [
      {
        team = "Q6L2SF6YDW";
        identifier = "com.anthropic.claude-code";
      }
      {
        team = "2DC432GLL2";
        identifier = "codex";
      }
    ];
  };

  # Headless tailscaled (no GUI app). One-time join after first switch:
  #   sudo tailscale up --auth-key=<oauth-minted key, tag:oauth-generated> --hostname=mac-mini
  services.tailscale.enable = true;

  # Wi-Fi is this box's only uplink and sometimes degrades to near-total
  # packet loss while staying associated; the watchdog power-cycles it
  # (modules/wifi-watchdog.nix). Mini only: on the laptop, captive portals
  # and travel networks would trip it.
  services.wifi-watchdog.enable = true;

  # trusted = true feeds Homebrew's tap-trust store at activation.
  homebrew.taps = [
    {
      name = "steipete/tap";
      trusted = true;
    }
    {
      name = "rjyo/moshi";
      trusted = true;
    }
  ];
  homebrew.brews = [
    # iMessage CLI for operator use. Not in nixpkgs.
    "steipete/tap/imsg"
    # Native UI batch automation for headless operators; no laptop UI control.
    "steipete/tap/peekaboo"
    # Moshi (phone terminal) agent daemon: surfaces Claude Code sessions on
    # this Mac in the Moshi app (inbox, waiting-state pushes, diffs). Runs as
    # a brew launchd service. One-time pairing: the moshi-pairing
    # manual step below; the Claude Code hooks it wants live in
    # agent-config's settings.json (nix-managed, read-only here).
    {
      name = "rjyo/moshi/moshi-hook";
      start_service = true;
    }
  ];

  # GUI apps that aren't packaged well in nixpkgs on macOS.
  homebrew.casks = [
    # @latest tracks releases faster than the plain cask; fable-5-1 needs >= 2.1.251
    "claude-code@latest"
    # nixpkgs lags upstream by several releases; see home/codex.nix.
    "codex"
    # ntn — home/ai-agent.nix's host-layer sibling (not in nixpkgs).
    "notion-cli"
    # Browser for agent-driven web work (chrome-control / web-recon).
    "google-chrome"
  ];

  # Flighty Sync reads the mini's local Flighty copy. The laptop already
  # installs Flighty; only the always-on mini will run the nightly mirror.
  homebrew.masApps."Flighty" = 1358823008;
  # MAS relies on Spotlight; the App Store receipt also proves installation.
  # Keep the declaration so a replacement Mac still installs Flighty.
  homebrew.extraConfig = ''
    if File.file?("/Applications/Flighty.app/Contents/_MASReceipt/receipt")
      ENV["HOMEBREW_BUNDLE_MAS_SKIP"] = [ENV["HOMEBREW_BUNDLE_MAS_SKIP"], "1358823008"].compact.join(" ")
    end
  '';
  services.flighty-sync = {
    enable = true;
    user = username;
  };

  # Weekly Apple-data snapshots (Sun 05:00 / 05:05). Each module installs a
  # signed .app + launchd agent; the one manual step per app is a Full Disk
  # Access grant (README §6). Output lands in iCloud-synced ~/Documents.
  services.screentime-backup = {
    enable = true;
    user = username;
    # After every snapshot (weekly, or kicked by a dashboard refresh) rebuild
    # and push the dashboard's series - inside the FDA-holding backup process.
    postRun = config.services.screentime-ingest.syncCommand;
    skipDumpFlag = config.services.screentime-ingest.skipDumpFlag;
  };
  services.screentime-ingest = {
    enable = true;
    user = username;
    url = "https://screentime-dashboard.nqipomyrjb.workers.dev";
  };
  # Media Center YouTube offline copies. A subscription has exactly one
  # consumer, so only this always-on Mac runs it (the laptop never does). The
  # job's own hub token lives in the login Keychain (manual step below).
  services.media-center.youtube-offline = {
    enable = true;
    user = username;
    hubUrl = "https://life-data.nqipomyrjb.workers.dev";
    subscriptionId = "0b06361f-3efa-422c-ae97-1d671f700d3c";
    credentialCommand = [
      "/usr/bin/security" "find-generic-password"
      "-s" "media-center.youtube-offline" "-a" "hub" "-w"
    ];
  };
  # Networth finance reviews started from the dashboard land here as Herdr
  # tabs. Outbound long poll only; the host credential is in the login
  # Keychain (manual step below).
  services.networth-host = {
    enable = true;
    user = username;
    url = "https://networth.nqipomyrjb.workers.dev";
    herdrWorkspace = "w1";
  };
  services.callhistory-backup = {
    enable = true;
    user = username;
    # WhatsApp cask + keep-alive come from the module (its runtime dep for
    # third-party call durations). One-time QR link — README §6.
    installWhatsApp = true;
  };

  # The one browser every agent job on this Mac drives (modules/agent-chrome.nix):
  # a headed Chrome on its own data dir, remote debugging on 9222, started at
  # login. Logins done in its window - by a job or by Alex over Screen
  # Sharing - persist for everything that attaches later.
  services.agent-chrome = {
    enable = true;
    user = username;
    # Claude in Chrome: its tabGroups permission is what chrome-control's
    # cdp-group.mjs borrows to give every agent session its own tab group.
    # Sign-in is manual (agent-chrome-login manual step below).
    extensions = [ "fcoeoabgfenejglbffodgkkbkcdhcgfn" ];
  };

  # The mini's ONE agenix secret: the mac-mini-machine 1P service-account
  # token (read-only on the "Mac Mini" vault), used only by explicit initial
  # bootstrap commands; see secrets/secrets.nix.
  age.secrets.machine-sa = {
    file = ../secrets/machine-sa-mini.age;
    owner = username;
    # agenix's default group reads users.users.<name>.group, which nix-darwin
    # does not define - eval fails with "attribute 'group' missing". Set it.
    group = "staff";
  };

  # Human steps nix cannot do (rendered into MANUAL-<host>.md; verified by manual-check).
  manual.steps = {
    flighty-sync = {
      title = "Open Flighty and finish iCloud sync";
      owner = "flighty-sync";
      desktop = true;
      body = ''
        If activation stops at the App Store administrator prompt, open Terminal
        through Screen Sharing and run `cd ~/.config/nix-config && just switch`;
        enter the administrator password when the App Store helper requests it.
        Then open Flighty on this Mac. Complete its first-run
        screens and any Apple/iCloud sign-in or purchase-restore prompt using
        the same account as the existing Flighty library. Allow its flights
        to finish syncing, then compare the list with a fresh Flighty export.
        Do not create a second account or import the existing flights again.
        A populated local database proves local availability only; Flighty Sync
        must separately verify source freshness and Life Data enrollment before
        its nightly sync is considered active.
      '';
      verify = ''
        test -d /Applications/Flighty.app && test -s "$HOME/Library/Containers/com.flightyapp.flighty/Data/Documents/MainFlightyDatabase.db"
      '';
      redo = "After replacing this Mac, signing out of iCloud, or resetting Flighty data.";
    };
    flighty-sync-enrollment = {
      title = "Enroll Flighty Sync and verify a complete run";
      owner = "flighty-sync";
      desktop = true;
      body = ''
        After Flighty's library has hydrated, use the installed CLI in Terminal:
        `flighty-sync configure --hub-url https://life-data.nqipomyrjb.workers.dev`,
        then `flighty-sync inspect` and
        `flighty-sync verify-export "$HOME/Documents/manual-backups/flighty/FlightyExport-2026-10-07.csv"`.
        Use a newly exported CSV if the library has changed. For a new machine,
        copy the official export through the normal user file interface first.

        The Life Data operator must publish the cataloged `flights` table and
        mint a dedicated `flighty-sync` consumer token with exactly
        `tables:read:flights,tables:write:flights,files:read:raw/flighty/,files:write:raw/flighty/`.
        From an enrolled operator terminal, run `life sync` to publish the
        local catalog before enrollment. Then `life token create flighty-sync
        --scopes "$(flighty-sync scopes)"` prints the token once. Never substitute
        an operator, full-replica or another consumer's token. Enter it without
        shell history using:

        ```zsh
        (
          read -rs 'flighty_sync_token?Flighty Sync consumer token: ' || exit
          printf '\n'
          printf '%s' "$flighty_sync_token" | flighty-sync login --token-stdin
        )
        ```

        Login validates the grants and saves the credential in native Keychain.
        The login Keychain must be accessible to the scheduled user agent.
        Each run opens Flighty in the background to resume native iCloud sync;
        hydration can finish after the snapshot and appear on the next run.
        If source access is denied, grant `/Applications/FlightySync.app`
        Full Disk Access in System Settings, Privacy & Security.
        Run `flighty-sync doctor` in the mini desktop Terminal; SSH shells cannot
        read this native Keychain credential. Then kick the installed job with
        `launchctl kickstart gui/$(id -u)/org.flighty-sync` and inspect
        `flighty-sync status`. A success must include verified archive readback
        and matching Life Data rows. Repeat after a known Flighty UI change and
        verify that iCloud brings it to this mini. A successful installed-context
        run verifies the nightly 03:30 job. iCloud freshness remains unverified
        until a known change has propagated from another device.
      '';
      verify = ''
        launchctl print gui/$(id -u)/org.flighty-sync | /usr/bin/grep -q 'last exit code = 0' &&
        flighty-sync status | ${pkgs.jq}/bin/jq -e '.state == "success"'
      '';
      redo = "After replacing the Mac, resetting Keychain, changing the source or service, or revoking the consumer credential.";
    };
    tcc-grants = {
      title = "TCC grants";
      owner = "tcc";
      phase = "snapshot";
      desktop = true;
      verify = "capture-snapshot tcc --diff ${../snapshots/mac-mini/tcc.txt}";
      body = ''
        System Settings → Privacy & Security (over Screen Sharing). The committed
        capture `snapshots/mac-mini/tcc.txt` IS the intended grant set
        (`capture-snapshot tcc`; refresh with `just snapshot tcc mac-mini`); audit
        and purge per docs/tcc.md.
      '';
    };
    screentime-backup-fda = {
      title = "ScreenTimeBackup.app + CallHistoryBackup.app Full Disk Access";
      owner = "screentime-backup";
      desktop = true;
      body = ''
        Grant Full Disk Access once per app - System Settings → Privacy & Security →
        **Full Disk Access** → **\[+]** → `/Applications/ScreenTimeBackup.app` and
        `/Applications/CallHistoryBackup.app`, toggle on. Each app is re-signed with
        its same stable cert every rebuild, so the grants persist. Verify:
        `launchctl kickstart -k gui/$(id -u)/com.alexmiller.screentime-backup` (and
        `...callhistory-backup`), then check `~/Library/Logs/<name>.log` for
        `backup OK` lines (a `cannot read` line means the grant is missing).
      '';
      verify = "grep -q 'backup OK' ~/Library/Logs/screentime-backup.log && grep -q 'backup OK' ~/Library/Logs/callhistory-backup.log";
    };
    media-center-youtube-offline = {
      title = "Media Center YouTube offline hub credential";
      owner = "media-center";
      desktop = true;
      body = ''
        The job's own Life Data token (operator copy: `Media Center YouTube Offline
        Life Data Token` in the Media Center vault) must be in the login Keychain as
        service `media-center.youtube-offline`, account `hub`. SSH sessions cannot
        write the Keychain: from the desktop session (a terminal over Screen Sharing,
        or a one-shot launchd job in `gui/$(id -u)`), pipe
        `add-generic-password -A -U -s media-center.youtube-offline -a hub -w <token>`
        into `security -i` on stdin. Then
        `launchctl kickstart -k gui/$(id -u)/com.alexmiller.media-center.youtube-offline`
        and check `~/.local/state/media-center/youtube-offline/youtube-offline.log`
        for a `watching` line without `hub` warnings.
      '';
      verify = "security find-generic-password -s media-center.youtube-offline -a hub >/dev/null";
      redo = "On a replacement Mac (mint a new token, revoke the old one) or after rotating the token.";
    };
    networth-host-enroll = {
      title = "Networth finance host enrollment";
      owner = "networth";
      desktop = true;
      body = ''
        Enroll from the login session (the Keychain is locked over ssh): either a
        desktop terminal over Screen Sharing running `networth-host enroll --label
        "Mac mini"`, or a one-shot `launchctl submit -l networth-enroll -o <log>
        -e <log> -- /run/current-system/sw/bin/networth-host enroll --label "Mac
        mini"` and read the approval link from the log. Open the link in a browser
        signed in to the Networth site, match the code and approve. Then
        `launchctl kickstart -k gui/$(id -u)/networth-host` and check
        `~/.local/state/networth-host/networth-host.log` for `polling`.
        Revoke a replaced host on the site's Widgets page.
      '';
      verify = "test -s ~/.local/state/networth-host/enrollment.json";
      redo = "on a replacement machine (revoke the old host on /widgets)";
    };
    screentime-dashboard-upload = {
      title = "Screentime Dashboard upload device";
      owner = "screentime-dashboard";
      desktop = true;
      body = ''
        Run `screentime-ingest login --no-browser`
        in a terminal on the mini's desktop through Screen Sharing. SSH sessions
        can reject Keychain writes with `User interaction is not allowed`.
        Open the printed link in an authenticated
        dashboard browser, match its approval code, and approve the upload device.
        The CLI stores its own revocable upload credential in macOS Keychain.
        Keep that user's login Keychain unlocked for the watcher and backup hook;
        native Keychain prompts must be approved on the desktop. Verify an actual
        dashboard Refresh completes, including its import stage. Replacement
        machines enroll again; revoke the replaced uploader in Upload devices.
        `screentime-ingest logout` revokes the current uploader and removes its
        local credential. Neither path uses the machine bootstrap vault.
      '';
      redo = "on a replacement machine (revoke the old uploader)";
    };
    ssh-screen-control = {
      title = "See + click the screen from ssh (agents)";
      owner = "mac-control";
      desktop = true;
      body = ''
        Every ssh-spawned process is
        attributed by TCC to `/usr/libexec/sshd-keygen-wrapper`, so grant that ONE
        binary, via Screen Sharing: System Settings → Privacy & Security →
        **Screen Recording** → \[+] → ⌘⇧G → `/usr/libexec/sshd-keygen-wrapper`,
        toggle on; same under **Accessibility**. Then from an ssh shell run
        `osascript -e 'tell application "System Events" to get name of every process'`
        once and click **Allow** on the "sshd-keygen-wrapper wants to control
        System Events" dialog that appears on the mini's display. Verify:
        `screencapture -x /tmp/s.png && file /tmp/s.png` (a real PNG, not black)
        and `osascript -e 'tell application "System Events" to click at {10, 10}'`
        (no -1719/-1743 error). After this, agents screenshot with
        `screencapture`, click/type with System Events, and can dismiss later
        dialogs themselves; only these grants and anything asking for the admin
        password stay human.
      '';
      verify = "screencapture -x /tmp/manual-check.png && file /tmp/manual-check.png | grep -q PNG";
    };
    moshi-pairing = {
      title = "Moshi pairing";
      owner = "moshi-hook";
      body = ''
        The brew formula, its
        launchd service, and the Claude/Codex hooks are declared. Moshi owns its
        pairing and recovery; no machine vault or service account restores it.
        An already-paired machine keeps its current native state: preserve
        `~/.config/moshi/` and `~/Library/Application Support/Moshi/`, including
        `secrets.json`, `config.json` and any `config.toml`. Do not re-pair or
        unpair it as part of a Nix rebuild.

        On a new or unpaired machine, get a pairing token from the Moshi iPhone
        app's Settings → Integrations. Check `moshi-hook pair --help` for the
        installed version. In an interactive zsh session, use a hidden prompt
        and Moshi's `MOSHI_PAIRING_TOKEN` environment input so the token is not
        entered in command history or passed as a command-line argument:

        ```zsh
        (
          read -rs 'moshi_pairing_token?Moshi pairing token: ' || exit
          printf '\n'
          MOSHI_PAIRING_TOKEN="$moshi_pairing_token" moshi-hook pair --store file
        )
        ```

        `--store file` uses Moshi's native 0600 `~/.config/moshi/secrets.json`
        storage for headless sessions where Keychain is unavailable. Moshi
        remembers the selected store; macOS otherwise defaults to Keychain.
        Keep native files writable by the user and outside the Nix store.
        Do not run `moshi-hook install` here: its Claude/Codex hooks are already
        declared. After pairing a new host, restart its existing Homebrew service
        and verify pairing with `moshi-hook status` and the phone app.
      '';
      verify = "/opt/homebrew/bin/moshi-hook status";
      redo = "on a new or unpaired machine only";
    };
    messages-sms-forwarding = {
      title = "Messages sign-in + SMS forwarding";
      owner = "messages";
      desktop = true;
      body = ''
        Via Screen Sharing sign Messages
        into iMessage, then on the iPhone Settings → Messages → **Text Message
        Forwarding** → enable this mini. Verify with
        `sqlite3 ~/Library/Messages/chat.db "select count(*) from message where service='SMS'"`
        (non-zero = forwarding works; `imsg`/sqlite readers need Full Disk Access).
      '';
      verify = "[ \"$(sqlite3 ~/Library/Messages/chat.db \"select count(*) from message where service='SMS'\")\" -gt 0 ]";
    };
    whatsapp-companion = {
      title = "WhatsApp companion device";
      owner = "whatsapp";
      desktop = true;
      body = ''
        Via Screen Sharing,
        open WhatsApp once → Settings on the iPhone → Linked Devices → Link a Device
        → scan the QR on the mini's screen. The keep-alive agent keeps it running
        afterward; no re-linking needed as long as the phone comes online every
        14 days and the app keeps running.
      '';
    };
    agent-chrome-login = {
      title = "Sign the agent Chrome into Claude in Chrome and Google";
      owner = "agent-chrome";
      desktop = true;
      body = ''
        The extension itself is policy-installed (`services.agent-chrome.extensions`
        → `chrome.policy`, mandatory via Managed Preferences; it appears a minute or
        two after the first switch + Chrome relaunch). Its sign-in is per profile and
        manual: over Screen Sharing, in the **agent Chrome's** window (the one on
        port 9222, not the default profile), click the Claude toolbar icon → sign in.
        Also sign that browser into Google (Chrome profile menu) - the Web Store and
        Google-backed sites ask for it. Its `tabGroups` permission is what
        chrome-control's `cdp-group.mjs` borrows to give every agent session its own
        window + tab group; verify from the laptop:
        `ssh -N -L 9223:127.0.0.1:9222 mac-mini-tailscale &` then
        `node ~/.claude/skills/chrome-control/scripts/cdp-group.mjs test https://example.com --port 9223`
        (prints `window=… group=…`), then the same with `--close`.
      '';
    };
    agent-chrome-sync-types = {
      title = "Agent Chrome sync types for the compliance skill";
      owner = "agent-chrome";
      desktop = true;
      body = ''
        The compliance skill's browser scan reads the iPhone's synced tabs and the
        saved tab groups from this agent Chrome profile, and its remote group
        deletion (closes the group on the phone too) needs the same sync. Sync state
        is per profile and manual; Nix cannot force sync types on. In the **agent
        Chrome's** window, open `chrome://settings/syncSetup/advanced` and turn on
        **Open tabs** and **Saved tab groups** only; leave History off. On builds
        where the page shows one combined "History and tabs" switch, the per-type
        rows are still there with zero size - drive them from the laptop through
        CDP (`cdp-eval.mjs` with a synthetic `.click()` on the `cr-toggle` whose row
        text starts with the type name). Leave the settings page afterwards: an open
        sync setup page holds the type from starting. Verify on
        `chrome://sync-internals/`: Sessions and Saved Tab Group = Running, History
        = Not Running. Then, in an agent shell on this machine, point the skill at
        its local Chrome and the phone (IDs from a first `scan browser`):
        `compliance.py connections set browser port 9222` and
        `compliance.py connections set browser phone-session <foreign_session.id>`.
      '';
    };
  };

}
