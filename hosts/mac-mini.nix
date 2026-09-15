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

  # Headless tailscaled (no GUI app). One-time join after first switch:
  #   sudo tailscale up --auth-key=<oauth-minted key, tag:oauth-generated> --hostname=mac-mini
  services.tailscale.enable = true;

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
    # Moshi (phone terminal) agent daemon: surfaces Claude Code sessions on
    # this Mac in the Moshi app (inbox, waiting-state pushes, diffs). Runs as
    # a brew launchd service. One-time pairing + hook install in
    # MANUAL-mac-mini.md §6; the Claude Code hooks it wants live in
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
    # Sign-in is manual (MANUAL-mac-mini.md).
    extensions = [ "fcoeoabgfenejglbffodgkkbkcdhcgfn" ];
  };

  # The mini's ONE agenix secret: the mac-mini-machine 1P service-account
  # token (read-only on the "Mac Mini" vault), used only by explicit initial
  # bootstrap commands; see secrets/secrets.nix.
  age.secrets.machine-sa = {
    file = ../secrets/machine-sa-mini.age;
    owner = username;
  };


  # Human steps nix cannot do (rendered into MANUAL-<host>.md; verified by manual-check).
  manual.steps = {
    screentime-backup-fda = {
      title = "ScreenTimeBackup.app + CallHistoryBackup.app Full Disk Access";
      owner = "screentime-backup";
      desktop = true;
      body = ''
        + **callhistory-backup** (weekly Apple-data snapshots):
        grant Full Disk Access once per app - System Settings → Privacy & Security →
        **Full Disk Access** → **\[+]** → `/Applications/ScreenTimeBackup.app` and
        `/Applications/CallHistoryBackup.app`, toggle on. Each app is re-signed with
        its same stable cert every rebuild, so the grants persist. Verify:
        `launchctl kickstart -k gui/$(id -u)/com.alexmiller.screentime-backup` (and
        `...callhistory-backup`), then check `~/Library/Logs/<name>.log` for
        `backup OK` lines (a `cannot read` line means the grant is missing).
      '';
      verify = "grep -q 'backup OK' ~/Library/Logs/screentime-backup.log && grep -q 'backup OK' ~/Library/Logs/callhistory-backup.log";
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
      verify = "moshi-hook status";
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
