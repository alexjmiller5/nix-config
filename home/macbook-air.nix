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
  ];

  # Agent SA token file (~/.local/state/op/agent-sa-token), refreshed at every
  # login from the machine vault via the machine SA — see home/op-agent-sa.nix.
  opAgentSa = {
    tokenOpRef = "op://a4gdaq4rjdpewl4uppphpjqewm/qol7eck3fumtefiwyrw4w5m3pm/credential";
    tokenOpAuthFile = osConfig.age.secrets.machine-sa.path;
  };

  # Tab Copy's ⇧⌘C shortcut is NOT codified: it lives in Chrome's HMAC-signed
  # Secure Preferences (extensions.settings.<id>.commands), so an unsigned
  # external write is ignored on startup. Re-bind it by hand after an
  # extension reload — see MANUAL-macbook-air.md.

  # Lets CDP clients attach to the real logged-in Chrome (the chrome-control
  # skill's Tier 2); each connection still needs a manual "Allow" click.
  chrome.remoteDebugging.enable = true;

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
  };

  # Third-party app notification permissions (home/macos/notification-prefs.nix).
  # Snapshot of a live ncprefs dump 2026-09-01; the flags int is the whole
  # per-app state (allow + style + lock-screen bits). To change a setting:
  # change it in System Settings, re-capture (command in the module header),
  # paste the new int here - UI-only edits revert at the next switch. Apple
  # system entries are deliberately not pinned (they churn with OS updates).
  macos.notificationPrefs.apps = {
    "app.legcord.Legcord" = 8396814;
    "com.cron.electron" = 8396822;
    "com.dmitrynikolaev.numi" = 8396814;
    "com.eventur.Hide.me" = 8396814;
    "com.facebook.archon.developerID" = 278929422;
    "com.figma.Desktop" = 8396814;
    "com.flightyapp.flighty" = 807411726;
    "com.google.Chrome" = 8396814;
    "com.google.Chrome.framework.AlertNotificationService" = 8396822;
    "com.haystacksoftware.ArqMonitor" = 276832270;
    "com.hnc.Discord" = 276832270;
    "com.kishanbagaria.jack" = 276832262;
    "com.mitchellh.ghostty" = 268443662;
    "com.openai.chat" = 276832262;
    "com.spotify.client" = 8396814;
    "com.tinyspeck.slackmacgap" = 8396814;
    "io.ipfs.desktop" = 8396814;
    "io.robbie.HomeAssistant" = 270540814;
    "io.tailscale.ipn.macsys" = 276832270;
    "net.whatsapp.WhatsApp" = 278929422;
    "notion.id" = 8396814;
    "notion.mail.id" = 8396814;
    "org.chromium.Chromium" = 8396814;
    "org.hammerspoon.Hammerspoon" = 8396822;
    "org.qbittorrent.qBittorrent" = 8396814;
    "pro.betterdisplay.BetterDisplay" = 276832270;
    "ru.keepcoder.Telegram" = 276832270;
    "us.zoom.xos" = 276832270;
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

  # Menu bar system-module ORDER (right → left below). ControlCenter honors
  # relative "Preferred Position" plain-domain values at launch (macOS 26,
  # verified 2026-08-04). On-demand command, not activation: ControlCenter
  # renormalizes the numbers after layout, so enforcing exact values every
  # switch would flap. Third-party icon order stays manual (⌘-drag) — see
  # MANUAL-macbook-air.md.
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

  # Commit signing via 1Password (desktop app + op-ssh-sign, laptop-only).
  # The signer script lives in agent-config, reached via the ~/.claude/skills
  # symlink so the path stays stable if the repo moves.
  programs.git.settings = {
    user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKWqJ5X61r/CFl99qjU/rZyIB4DCQpVI+cF0y33WSSMC";
    gpg.format = "ssh";
    gpg.ssh.program = "${config.home.homeDirectory}/.claude/skills/1password/scripts/op-ssh-sign-auto";
    commit.gpgsign = true;
  };

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

  # Workspace Snapshot — its flake's home-manager module (imported via
  # sharedModules in flake.nix) installs the Application Support scripts dir
  # the Claude SessionStart hook references and the VS Code terminals
  # extension. Replaces the repo's install.sh; updates ride the weekly flake
  # input bump. The Spoon itself is NOT symlinked anymore: the hammerspoon
  # repo vendors all spoons in-tree (real dir at the same path), so the
  # module's spoon file is disabled here.
  programs.workspace-snapshot.enable = true;
  home.file.".hammerspoon/Spoons/WorkspaceSnapshot.spoon".enable = false;

}
