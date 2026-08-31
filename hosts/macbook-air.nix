{
  config,
  pkgs,
  lib,
  username,
  ...
}:

# MacBook Air — the GUI-full host. The mini matches it at the shell/dev
# level (see home/dev-tools.nix + home/mac-mini.nix); this host adds the GUI
# layer (casks, dock, Chrome policy, yabai) and the Apple build chain, and
# lacks the mini's headless-server bits (never-sleep power, headless
# tailscaled, callhistory backup). Home profile: home/macbook-air.nix.
# Shared base (stateVersion, unfree predicate, /etc/nix-darwin, brew zap, …)
# comes from modules/darwin-base.nix via mkHost.
{
  imports = [
    ../modules/notunes.nix
    ../modules/chrome-policy.nix
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

  # yabai: the org.nixos.yabai launchd agent runs the nix package for BSP
  # tiling. The scripting addition is OFF — macOS 26.1's AMFI enforces library
  # validation on Dock (a platform binary) and refuses to load yabai's
  # third-party ad-hoc payload, so SA-only features (space create/destroy,
  # cross-display space moves, opacity, sticky windows) don't work regardless
  # of SIP state. With the SA off there's no yabai-sa daemon and no
  # /etc/sudoers.d/yabai. Still manual: granting Accessibility when the store
  # path changes on upgrades (MANUAL-macbook-air.md). Revisit if yabai ships
  # real macOS 26.x injection support.
  #
  # config.layout is set purely so the module writes a yabairc and passes
  # `-c` — without any config yabai warns "could not locate config file" on
  # every start. `float` matches yabai's own default (no auto-tiling); switch
  # to "bsp" here for automatic tiling.
  services.yabai = {
    enable = true;
    config.layout = "float";
  };

  # Disable auto display brightness (laptop-only; written to /Library/Preferences
  # as root — takes effect after a restart).
  system.defaults.CustomSystemPreferences = {
    "/Library/Preferences/com.apple.iokit.AmbientLightSensor" = {
      "Automatic Display Enabled" = false;
    };
  };

  # Laptop-only root activation steps (Rosetta, yabai TCC nudge). The cask
  # de-quarantine lives in darwin-base.nix (both machines); chrome-policy.nix
  # contributes its own entry too — the option is types.lines, so all the
  # definitions merge.
  system.activationScripts.postActivation.text = ''
    # Rosetta 2, declared (needed by EGGNOGG+ in home/macbook-air.nix —
    # x86_64-only). No nix-darwin option exists; activation runs as root,
    # so install here, guarded by the oahd check to stay idempotent.
    if ! /usr/bin/pgrep -q oahd; then
      /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    fi

    # yabai TCC reminder: Accessibility grants key on the nix store path,
    # which changes on version bumps — the old grant dies and the keepalive
    # agent spams Accessibility prompts (MANUAL-macbook-air.md). Compare
    # against the last-switched path and print re-grant instructions.
    yabaiBin='${config.services.yabai.package}/bin/yabai'
    if [ "$(cat /var/db/yabai-tcc-path 2>/dev/null)" != "$yabaiBin" ]; then
      printf '\n\033[1;33myabai store path changed — re-grant Accessibility or the prompt spam returns:\033[0m\n'
      echo "  System Settings > Privacy & Security > Accessibility:"
      echo "    1. remove the stale yabai row (minus button)"
      echo "    2. + > Cmd+Shift+G > paste: $yabaiBin"
      echo "    3. toggle it ON"
      echo "$yabaiBin" > /var/db/yabai-tcc-path
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
    { app = "/Applications/Gemini.app"; }
    { app = "/Applications/Claude.app"; }
    { app = "/Users/${username}/Applications/Chrome Apps.localized/Google Maps.app"; }
  ];

  # Brew-ONLY leftovers — everything available in nixpkgs migrated to
  # home/macbook-air.nix home.packages on 2026-08-10 (dep cruft and the
  # unused ruby managers dropped outright; brew auto-keeps real deps).
  homebrew = {
    # trusted = true feeds Homebrew's tap-trust store at activation — without
    # it brew ignores the tap's formulae/casks entirely.
    taps = [
      # Alex's personal cask tap — apps released by their repos' CI
      # (gemini-desktop, receptor, ...).
      {
        name = "alexjmiller5/tap";
        trusted = true;
      }
      {
        name = "smudge/smudge";
        trusted = true;
      }
      {
        name = "steipete/tap";
        trusted = true;
      }
    ];
    brews = [
      "chrome-cli"
      "skills"
      "smudge/smudge/nightlight"
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
      "claude"
      "claude-code"
      "codexbar"
      "discord"
      "docker-desktop"
      "dolphin"
      # From alexjmiller5/tap — released + notarized by gemini-desktop's CI.
      # Replaces the old imperative install.sh install. MUST stay fully
      # qualified: bare "gemini" is MacPaw's disk cleaner in homebrew/cask.
      "alexjmiller5/tap/gemini"
      "ghostty"
      "google-chrome"
      "hammerspoon"
      "karabiner-elements"
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
}
