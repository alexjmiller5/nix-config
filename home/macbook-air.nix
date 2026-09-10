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
#    For configs their apps never write and no HM module covers (karabiner).
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
    ./ai-agent.nix
    ./dev-tools.nix
    ./zsh.nix
    ./aliases/dev.nix
    ./aliases/ai.nix
    ./aliases/infra.nix
    ./macos/menu-bar.nix
    ./macos/spotlight-raycast.nix
    ./macos/nightlight.nix
    ./macos/duti.nix
    ./macos/chrome-extension-storage.nix
    ./macos/chrome-remote-debugging.nix
    ./macos/notification-prefs.nix
    ./ghostty.nix
    ./spotify-player.nix
    ./vscode.nix
    ./agents.nix
    ./ssh.nix
    ./agent-ssh-agent.nix
  ];

  # Dedicated ssh-agent for agent shells, loaded at login from the AI Agent
  # vault via the agent SA token file - lets unattended agent sessions ssh to
  # the mini with no 1Password approval dialog (see home/agent-ssh-agent.nix).
  # Item: "AI Agent Mac Mini SSH Key".
  agentSshAgent = {
    keyOpRefs = [ "op://4eeyrkqibibn7k4j6rz2fbzvxm/im7srzb2x7sy2d3kj3mpy7svai/private key" ];
    tokenFile = "${config.home.homeDirectory}/.local/state/op/agent-sa-token";
  };

  # Agent SA token file (~/.local/state/op/agent-sa-token), refreshed at every
  # login from the machine vault via the machine SA — see home/op-agent-sa.nix.
  opAgentSa = {
    tokenOpRef = "op://a4gdaq4rjdpewl4uppphpjqewm/qol7eck3fumtefiwyrw4w5m3pm/credential";
    tokenOpAuthFile = osConfig.age.secrets.machine-sa.path;
  };

  # Local trial on the laptop. The exported module remains opt-in on other
  # hosts; the mini keeps direct SA/desktop auth and needs no Docker runtime.
  opConnect = {
    enable = true;
    vaultId = "4eeyrkqibibn7k4j6rz2fbzvxm";
    credentialsItemId = "ztahtbkzccclf3nvchiwmrb7ci";
    tokenOpRef = "op://4eeyrkqibibn7k4j6rz2fbzvxm/qc67dntzaer2k4n3jx6baql7va/credential";
  };

  # Tab Copy's ⇧⌘C shortcut is NOT codified: it lives in Chrome's HMAC-signed
  # Secure Preferences (extensions.settings.<id>.commands), so an unsigned
  # external write is ignored on startup. Re-bind it by hand after an
  # extension reload — see MANUAL-macbook-air.md.

  # Lets CDP clients attach to the real logged-in Chrome (the chrome-control
  # skill's Tier 2); each connection still needs a manual "Allow" click.
  chrome.remoteDebugging.enable = true;

  # Where agents run their browser: the mini's shared agent Chrome
  # (hosts/mac-mini.nix services.agent-chrome), never this laptop's - the
  # chrome-control skill reads this and drives it over an ssh port-forward.
  home.sessionVariables.CHROME_CONTROL_HOST = "mac-mini-tailscale";

  # Tab Copy's custom "URL Format" (urls only, newline-delimited) — lives in
  # the extension's chrome.storage.local, wiped on reinstall. Captured from a
  # live plyvel dump 2026-08-18; edit here (or re-dump) after UI changes,
  # since these values are enforced over UI edits at every switch.
  chrome.extensionStorage = {
    profile = "Profile 1";
    storage.micdllihgoppmejpecmkilggmaagfdmb = {
      customFormatIds = [ "custom-9hVL4q" ];
      orderedFormatIds = [ "custom-9hVL4q" ];
      hiddenFormatIds = [ ];
      formatOpts."custom-9hVL4q" = {
        name = "URL Format";
        template = {
          start = "";
          end = "";
          tab = "[url]";
          tabDelimiter = "[n]";
          windowStart = "";
          windowEnd = "";
          windowDelimiter = "[n]";
        };
      };
    };

    # Claude in Chrome: the per-site grants behind the extension's own
    # "Allow / Always allow actions on this site" popup. That popup is a
    # focused chrome.windows.create — it is the ONLY thing that steals focus
    # during agent browsing, so a seeded grant here buys both no-prompt and
    # no-focus-steal. Claude Code's own terminal prompt is separate and is
    # handled in agent-config/claude/settings.json (the whole-tool
    # mcp__claude-in-chrome allow rule + CLAUDE_CHROME_CLASSIFIER_FLOOR=false).
    #
    # Matching: `netloc` is compared with `www.` and any port stripped, and a
    # leading `*.` also matches every subdomain. `surface` MUST stay
    # "mcp_popup" — grants with any other surface are ignored on this path.
    # Adding a site = one more entry; this list is enforced over UI edits at
    # every switch, so a site allowed by clicking the popup must be added
    # here too or it gets reverted.
    storage.fcoeoabgfenejglbffodgkkbkcdhcgfn.permissionStorage.permissions =
      map
        (netloc: {
          id = "nix-${builtins.replaceStrings [ "*" "." ] [ "star" "-" ] netloc}";
          action = "allow";
          duration = "always";
          surface = "mcp_popup";
          scope = {
            type = "netloc";
            inherit netloc;
          };
        })
        [
          "localhost"
          "127.0.0.1"
          "example.com"
          "iana.org"
        ];
  };

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
    "com.asmvik.yabai" = {
      enable = true;
      flags = 41951246;
      content_visibility = 0;
      grouping = 0;
    };
    "com.cron.electron" = {
      enable = false;
      flags = 8396822;
      content_visibility = 0;
      grouping = 0;
    };
    "com.electron.dockerdesktop" = {
      enable = false;
      flags = 8396814;
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

  # Machine-vault git bootstrap (home/machine-vault-git.nix): the laptop's
  # PAT is contents:write on exactly these repos — headless, so the launchd
  # sync agents keep pushing. Deliberately NOT write-broadened; general
  # pushes belong to the gh-wrapper PAT. hammerspoon (private) is cloned via
  # the gh default helper instead — switches run in Alex's desktop-authed
  # terminal, where that resolves.
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
    # build chain (Xcode-bound, iOS builds are laptop-by-design), GUI
    # helpers, and fonts.
    pkgs.create-dmg
    # VS Code's editor font — home-manager copies package fonts into
    # ~/Library/Fonts/HomeManager. Replaces the hand-installed ttfs.
    pkgs.fira-code
    pkgs.duti
    pkgs.fastlane
    pkgs.libimobiledevice
    pkgs.mas
    pkgs.xcodegen
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
    # stays manual (⌘-drag) — see MANUAL-macbook-air.md.
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
  xdg.configFile."karabiner/karabiner.json".source = ../dotfiles/karabiner/karabiner.json;

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

}
