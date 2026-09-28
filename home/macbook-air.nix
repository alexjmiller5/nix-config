{
  config,
  osConfig,
  pkgs,
  lib,
  username,
  ...
}:

# Laptop home profile: full shell + dotfiles + the agent-config fan-out.
#
# Two file-management modes in here, chosen per file:
#  - store symlink (home.file.source = ./path): immutable, edit via repo+rebuild.
#    For configs their apps never write and no HM module covers.
#  - mkOutOfStoreSymlink: symlink into a live git working copy — tracked, but
#    the app can write at runtime (VS Code settings, Claude settings, skills).
let
  # All companion working clones live in ~/.config (out of iCloud);
  # /etc/nix-darwin symlinks to nixConfig as the canonical rebuild path.
  nixConfig = "${config.home.homeDirectory}/.config/nix-config";
  agentConfig = "${config.home.homeDirectory}/.config/agent-config";
  mkLink = path: config.lib.file.mkOutOfStoreSymlink path;
in
{
  imports = [
    ./common.nix
    ./agent-machine.nix
    ./ai-agent.nix
    ./claude-rc.nix
    ./dev-tools.nix
    ./zsh.nix
    ./aliases/dev.nix
    ./aliases/ai.nix
    ./aliases/infra.nix
    ./macos/menu-bar.nix
    ./macos/spotlight-raycast.nix
    ./macos/nightlight.nix
    ./macos/duti.nix
    ./macos/chrome-remote-debugging.nix
    ./macos/notification-prefs.nix
    ./macos/window-management.nix
    ./macos/hyper-key.nix
    ./ghostty.nix
    ./spotify-player.nix
    ./vscode.nix
    ./agents.nix
    ./ssh.nix
    ./agent-ssh-agent.nix
  ];

  # Desktop preferences are useful on the laptop; the headless mini consumes
  # only the shared Finder baseline from common.nix.
  macos.finder.desktop.enable = true;

  # The interactive laptop uses Caps as Hyper; the headless mini does not.
  macos.hyperKey.enable = true;

  # Dedicated ssh-agent for agent shells, loaded at login from the AI Agent
  # vault via the agent SA token file - lets unattended agent sessions ssh to
  # the mini with no 1Password approval dialog (see home/agent-ssh-agent.nix).
  # Item: "AI Agent Mac Mini SSH Key".
  agentSshAgent = {
    keyOpRefs = [ "op://4eeyrkqibibn7k4j6rz2fbzvxm/im7srzb2x7sy2d3kj3mpy7svai/private key" ];
    tokenFile = "${config.home.homeDirectory}/.local/state/op/agent-sa-token";
  };

  # Inbound ssh from the mini's agent shells: public half of
  # "AI Agent MacBook Air SSH Key" (private half in the AI Agent vault, served
  # on the mini by home/agent-ssh-agent.nix). A real file, not home.file -
  # macOS sshd rejects an authorized_keys symlinked into /nix/store.
  home.activation.installAuthorizedKeys = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    rm -f "$HOME/.ssh/authorized_keys"
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEJiXPWpPMs7jNtXA0yrD9DP5/zmc3GQ0WZq4o5ZYWgY ai-agent-macbook-air' > "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
  '';

  # Local Connect on a colima VM (home/op-connect.nix); the mini enables the
  # same module with its own server.
  opConnect = {
    enable = true;
    vaultId = "4eeyrkqibibn7k4j6rz2fbzvxm";
    credentialsItemId = "ztahtbkzccclf3nvchiwmrb7ci";
    tokenOpRef = "op://4eeyrkqibibn7k4j6rz2fbzvxm/qc67dntzaer2k4n3jx6baql7va/credential";
  };

  # Chrome per-extension state is NOT codified - see the chrome snapshot manual steps (hosts/macbook-air.nix):
  #  - Tab Copy's ⇧⌘C shortcut lives in Chrome's HMAC-signed Secure
  #    Preferences (extensions.settings.<id>.commands), so an unsigned
  #    external write is ignored on startup.
  #  - Tab Copy's custom copy format and Claude in Chrome's per-site grants
  #    live in each extension's chrome.storage.local, a LevelDB Chrome keeps
  #    exclusively locked while it runs. Chrome is opened at login here, so an
  #    activation script never gets the lock. Both are recreated by hand.

  # Lets CDP clients attach to the real logged-in Chrome (the chrome-control
  # skill's Tier 2); each connection still needs a manual "Allow" click.
  chrome.remoteDebugging.enable = true;

  # Where agents run their browser: the mini's shared agent Chrome
  # (hosts/mac-mini.nix services.agent-chrome), never this laptop's - the
  # chrome-control skill reads this and drives it over an ssh port-forward.
  home.sessionVariables.CHROME_CONTROL_HOST = "mac-mini-tailscale";

  # Capability sheet this laptop's agent sessions load (home/agent-machine.nix).
  agentMachine.profile = lib.mkDefault "macbook";

  # Per-app notification settings, `enable` included (the "Allow
  # notifications" switch) - see home/macos/notification-prefs.nix.
  # Captured 2026-09-01 with `scripts/capture-notification-prefs`, which emits
  # this whole block for every still-installed app. Flip `enable` here to mute
  # or unmute an app declaratively; for anything else change it in System
  # Settings and re-run the script, since the ints are opaque macOS bitmasks.
  # UI-only edits revert at the next switch.
  macos.notificationPrefs.apps = {
    "com.alexmiller.receptor" = {
      enable = true;
      flags = 310386702;
      content_visibility = 0;
      grouping = 0;
    };
    "com.anthropic.claudefordesktop" = {
      enable = true;
      flags = 310386702;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.FaceTime" = {
      enable = false;
      flags = 278929422;
      content_visibility = 3;
      grouping = 0;
    };
    "com.apple.Family" = {
      enable = false;
      flags = 8396814;
      content_visibility = 3;
      grouping = 0;
    };
    "com.apple.FindMySafetyAlertsNotifications" = {
      enable = true;
      flags = 807403534;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.Maps" = {
      enable = true;
      flags = 271056910;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.MobileSMS" = {
      enable = false;
      flags = 9490137174;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.Music" = {
      enable = false;
      flags = 276832270;
      content_visibility = 3;
      grouping = 0;
    };
    "com.apple.Notes" = {
      enable = false;
      flags = 276832270;
      content_visibility = 3;
      grouping = 0;
    };
    "com.apple.Passwords" = {
      enable = false;
      flags = 276832270;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.Photos" = {
      enable = false;
      flags = 276832270;
      content_visibility = 3;
      grouping = 0;
    };
    "com.apple.Safari" = {
      enable = false;
      flags = 8396814;
      content_visibility = 3;
      grouping = 0;
    };
    "com.apple.Safari.WebApp" = {
      enable = true;
      flags = 268443662;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.ScriptEditor2" = {
      enable = true;
      flags = 41951246;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.Siri" = {
      enable = true;
      flags = 310386830;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.TV" = {
      enable = false;
      flags = 276832270;
      content_visibility = 3;
      grouping = 0;
    };
    "com.apple.TelephonyUtilities" = {
      enable = true;
      flags = 17221820430;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.appleseed.FeedbackAssistant" = {
      enable = true;
      flags = 268443662;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.clock" = {
      enable = true;
      flags = 8919720086;
      content_visibility = 3;
      grouping = 0;
    };
    "com.apple.dt.Xcode" = {
      enable = false;
      flags = 276832270;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.findmy" = {
      enable = false;
      flags = 1889533966;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.freeform" = {
      enable = true;
      flags = 176168974;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.iBooksX" = {
      enable = false;
      flags = 816324622;
      content_visibility = 3;
      grouping = 0;
    };
    "com.apple.iChat" = {
      enable = true;
      flags = 41943054;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.mail" = {
      enable = false;
      flags = 276824078;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.mobilephone" = {
      enable = false;
      flags = 278929422;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.news" = {
      enable = false;
      flags = 815800334;
      content_visibility = 3;
      grouping = 0;
    };
    "com.apple.podcasts" = {
      enable = false;
      flags = 832573454;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.shortcuts" = {
      enable = true;
      flags = 327680142;
      content_visibility = 0;
      grouping = 0;
    };
    "com.apple.weather" = {
      enable = false;
      flags = 832577550;
      content_visibility = 0;
      grouping = 0;
    };
    "com.cron.electron" = {
      enable = false;
      flags = 8396822;
      content_visibility = 0;
      grouping = 0;
    };
    "com.flightyapp.flighty" = {
      enable = false;
      flags = 815800334;
      content_visibility = 0;
      grouping = 0;
    };
    "com.google.Chrome" = {
      enable = false;
      flags = 8396814;
      content_visibility = 3;
      grouping = 0;
    };
    "com.google.Chrome.framework.AlertNotificationService" = {
      enable = false;
      flags = 17188266006;
      content_visibility = 3;
      grouping = 0;
    };
    "com.google.chrome.for.testing" = {
      enable = true;
      flags = 41951246;
      content_visibility = 0;
      grouping = 0;
    };
    "com.google.chrome.for.testing.framework.AlertNotificationService" = {
      enable = true;
      flags = 41951246;
      content_visibility = 0;
      grouping = 0;
    };
    "com.hnc.Discord" = {
      enable = false;
      flags = 276832270;
      content_visibility = 0;
      grouping = 0;
    };
    "com.microsoft.VSCode" = {
      enable = true;
      flags = 310386702;
      content_visibility = 0;
      grouping = 0;
    };
    "com.mitchellh.ghostty" = {
      enable = true;
      flags = 310386702;
      content_visibility = 0;
      grouping = 0;
    };
    "com.raycast.macos" = {
      enable = true;
      flags = 268443662;
      content_visibility = 0;
      grouping = 0;
    };
    "com.spotify.client" = {
      enable = false;
      flags = 276832270;
      content_visibility = 3;
      grouping = 0;
    };
    "com.steipete.codexbar" = {
      enable = true;
      flags = 310386702;
      content_visibility = 0;
      grouping = 0;
    };
    "com.steipete.repobar" = {
      enable = true;
      flags = 268443662;
      content_visibility = 0;
      grouping = 0;
    };
    "com.tinyspeck.slackmacgap" = {
      enable = false;
      flags = 8396814;
      content_visibility = 0;
      grouping = 0;
    };
    "io.tailscale.ipn.macsys" = {
      enable = false;
      flags = 276832270;
      content_visibility = 0;
      grouping = 0;
    };
    "net.whatsapp.WhatsApp" = {
      enable = false;
      flags = 278929422;
      content_visibility = 0;
      grouping = 0;
    };
    "notion.id" = {
      enable = false;
      flags = 276832270;
      content_visibility = 0;
      grouping = 0;
    };
    "org.hammerspoon.Hammerspoon" = {
      enable = false;
      flags = 8396822;
      content_visibility = 0;
      grouping = 0;
    };
    "pro.betterdisplay.BetterDisplay" = {
      enable = false;
      flags = 276832270;
      content_visibility = 0;
      grouping = 0;
    };
    "ru.keepcoder.Telegram" = {
      enable = false;
      flags = 276832270;
      content_visibility = 0;
      grouping = 0;
    };
    "us.zoom.xos" = {
      enable = false;
      flags = 276832270;
      content_visibility = 3;
      grouping = 0;
    };
  };

  # Explicit initial cloning only (home/machine-vault-git.nix). The machine
  # PAT is used only for these repos; all ongoing sync uses the operator gh
  # wrapper. hammerspoon uses gh even during bootstrap, so run the command
  # from a desktop-authenticated terminal after signing into 1Password.
  machineVaultGit = {
    patOpRef = "op://a4gdaq4rjdpewl4uppphpjqewm/kxvidplfszmwyaxke6sbwrbl5u/credential";
    patAuthFile = osConfig.age.secrets.machine-sa.path;
    patRepos = [
      "alexjmiller5/agent-config"
      "alexjmiller5/nix-secrets"
    ];
    companionRepos = {
      "alexjmiller5/nix-config" = nixConfig;
      "alexjmiller5/nix-secrets" = "${config.home.homeDirectory}/.config/nix-secrets";
      "alexjmiller5/agent-config" = agentConfig;
      # PUBLIC sibling of agent-config (generic skills); anonymous clone,
      # pushes ride the gh-wrapper default helper - not the machine PAT.
      "alexjmiller5/agent-config-public" = "${config.home.homeDirectory}/.config/agent-config-public";
      "alexjmiller5/hammerspoon" = "${config.home.homeDirectory}/.hammerspoon";
    };
  };

  # Keep ~/Desktop materialized (never iCloud-evicted) — symlink targets and
  # working clones live under it. Laptop-personal, so not a home/macos module.
  home.activation.pinDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "$(/usr/bin/xattr -p com.apple.fileprovider.pinned "$HOME/Desktop" 2>/dev/null)" != "1" ]; then
      /usr/bin/xattr -w com.apple.fileprovider.pinned 1 "$HOME/Desktop"
    fi
  '';

  home.packages = [
    # Laptop-only leftovers — the portable dev toolbox lives in
    # home/dev-tools.nix (shared with the mini). What stays here: the Apple
    # build chain pieces the mini does not need (fastlane, device tools), GUI
    # helpers, and fonts.
    pkgs.create-dmg
    # VS Code's editor font — home-manager copies package fonts into
    # ~/Library/Fonts/HomeManager. Replaces the hand-installed ttfs.
    pkgs.fira-code
    pkgs.duti
    pkgs.fastlane
    pkgs.libimobiledevice
    pkgs.mas
    # Tailscale CLI for the GUI app (tailscale-app cask ships no PATH binary) —
    # replaces the hand-written /usr/local/bin/tailscale shim.
    (pkgs.writeShellApplication {
      name = "tailscale";
      text = ''
        exec "/Applications/Tailscale.app/Contents/MacOS/Tailscale" "$@"
      '';
    })
    # EGGNOGG+ — full derivation in pkgs/eggnoggplus.nix (itch.io download
    # dance; x86_64-only, needs the Rosetta postActivation in the host file).
    (pkgs.callPackage ../pkgs/eggnoggplus.nix { })
    # Menu bar system-module ORDER (right → left, as listed below).
    # ControlCenter honors relative "Preferred Position" plain-domain values
    # at launch (macOS 26, verified 2026-08-04). An on-demand command, not an
    # activation step: ControlCenter renormalizes the numbers after layout, so
    # enforcing exact values every switch would flap. Third-party icon order
    # stays manual (⌘-drag) - the menu-bar-order manual step below.
    (pkgs.writeShellApplication {
      name = "menubar-layout";
      text = ''
        pos=110
        for mod in Sound WiFi Battery Bluetooth ScreenMirroring AirDrop; do
          /usr/bin/defaults write com.apple.controlcenter \
            "NSStatusItem Preferred Position $mod" -int "$pos"
          pos=$((pos + 50))
        done
        /usr/bin/killall ControlCenter 2>/dev/null || true
        echo "system modules re-laid out, right→left: Sound WiFi Battery Bluetooth ScreenMirroring AirDrop"
      '';
    })
  ];

  home.file.".hushlogin".text = "";

  # --- static dotfiles (read-only; edit in dotfiles/ + rebuild) ---
  # Finder quick action (right-click → Open in VS Code). pbs auto-registers
  # anything in ~/Library/Services; no further wiring needed.
  home.file."Library/Services/Open in VS Code.workflow".source =
    ../dotfiles/services + "/Open in VS Code.workflow";

  # --- VS Code (app-writable → out-of-store into THIS repo's working clone) ---
  home.file."Library/Application Support/Code/User/settings.json".source =
    mkLink "${nixConfig}/dotfiles/vscode/settings.json";
  home.file."Library/Application Support/Code/User/keybindings.json".source =
    mkLink "${nixConfig}/dotfiles/vscode/keybindings.json";

  # (agent-config fan-out symlinks come from home/agent-config-links.nix.)

  # Claude auto-memory lives in agent-config/memory/<cwd-slug>/, adopted and
  # linked by the agent-config-sync agent (home/agents.nix) — not here, so
  # adoption happens before that agent's commit rather than only at switch.

  # Hammerspoon profile selector — read by ~/.hammerspoon/init.lua at load.
  # The hammerspoon repo itself stays an independent live clone (never nix-managed).
  home.file.".config/hammerspoon-profile".text = "personal";

  # Human steps nix cannot do (rendered into MANUAL-<host>.md; verified by manual-check).
  manual.steps = {
    herdr-mini-machine = {
      title = "Herdr saved machine: the mini";
      owner = "herdr";
      body = ''
        Once, from a laptop terminal: `herdr machine add mac-mini-tailscale --label Mini`.
        Herdr starts the mini's server over ssh (keep it that way: an ssh-spawned
        server inherits the mini's `sshd-keygen-wrapper` TCC grants; a launchd
        server would not) and saves the profile in its client state. The sidebar
        then shows Local and Mini; agents on the mini report state and get the
        mini's capability sheet. After a mini reboot the client restarts the
        server over ssh by itself within a minute; only if the Mini row stays
        on Attention, run `herdr --remote mac-mini-tailscale` once and restart
        the client. Image handoff into a mini pane is ctrl+v (clipboard image),
        not drag-and-drop.
      '';
      verify = "herdr machine list --json | jq -e 'any(.[]; .label == \"Mini\")' >/dev/null";
    };
    menu-bar-order = {
      title = "Third-party menu bar icon order";
      owner = "menu-bar";
      phase = "snapshot";
      desktop = true;
      body = ''
        Manual: THIRD-PARTY icon order (⌘-drag). Can't sanely be declared: each
        app's spot is an `"NSStatusItem Preferred Position"` pixel-offset key in
        that app's own defaults domain, reread only at app launch - and apps that
        skip `autosaveName` (e.g. CodexBar) get no position persistence from macOS
        at all. If arrangement drift ever gets annoying, the Thaw cask
        (Accessibility-based layout profiles) is the tool-shaped answer. Full
        research: Notion note "Menu bar / dock in nix - findings" (2026-08-02).

        Reference layout, right → left (snapshotted 2026-08-04): clock,
        Control Center, Sound, WiFi, BetterDisplay, Tailscale, Battery, Bluetooth,
        Screen Mirroring, Weather, 1Password, AirDrop, RepoBar, CodexBar.
      '';
    };
    notification-sources = {
      title = "OS notification sources stay undeclared";
      owner = "notification-prefs";
      phase = "snapshot";
      body = ''
        Manual: the OS's own notification sources (Wi-Fi, Bluetooth, Software Update,
        tccd - the `_SYSTEM_CENTER_:` entries and the bundles under
        `/System/Library/UserNotifications/`) are deliberately left undeclared; their
        values churn with OS updates.
        What IS declared, and the usernoted store gotchas: docs/notifications.md.
      '';
    };
  };

}
