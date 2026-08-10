{ pkgs, lib, username, ... }:

# MacBook Air — LIVE since 2026-07-28 (generation 1). Mirrors the mini minus
# its headless-server bits (never-sleep power settings, headless tailscaled)
# and its data-collection services (screentime/callhistory/finance-sync — the
# flake imports those modules for every host, but only mac-mini.nix enables
# them). Home profile: home/macbook-air.nix.
{
  imports = [ ../modules/notunes.nix ];

  system.stateVersion = 6;
  system.primaryUser = username;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # The 1Password CLI (op) — used by the git credential helper — is unfree.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "1password-cli" ];

  # The laptop's ONE agenix secret: the macbook-air-machine 1P service-account
  # token (read-only on the "MacBook Air" vault). Every other secret lives in
  # that vault, fetched at runtime via op read — see secrets/secrets.nix.
  age.secrets.machine-sa = {
    file = ../secrets/machine-sa-laptop.age;
    owner = username;
  };

  # The laptop's nix came from the standalone installer, which manages the
  # daemon itself; nix-darwin must not.
  nix.enable = false;

  # The laptop has a normal pre-existing /opt/homebrew; let nix-homebrew
  # adopt it on first activation instead of erroring.
  nix-homebrew.autoMigrate = true;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  environment.systemPackages = with pkgs; [
    git
    just
  ];

  # Canonical flake location: darwin-rebuild finds /etc/nix-darwin/flake.nix on
  # its own, so rebuild commands never need to know where the working clone
  # lives. A string (not a path literal) keeps the symlink out-of-store.
  environment.etc."nix-darwin".source = "/Users/${username}/.config/nix-config";

  # Tailscale runs via the GUI app (tailscale-app cask below), unlike the
  # mini's headless tailscaled.

  # Disable auto display brightness (laptop-only; written to /Library/Preferences
  # as root — takes effect after a restart).
  system.defaults.CustomSystemPreferences = {
    "/Library/Preferences/com.apple.iokit.AmbientLightSensor" = {
      "Automatic Display Enabled" = false;
    };
  };

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
    { app = "/Users/alexmiller/Applications/Chrome Apps.localized/Google Maps.app"; }
  ];

  # Snapshot of the laptop's imperatively-installed brew state (refreshed
  # 2026-07-28 during Phase 0 reconcile), so the first switch changes nothing.
  homebrew = {
    enable = true;
    taps = [
      # Alex's personal cask tap — apps released by their repos' CI
      # (gemini-desktop, receptor, ...).
      "alexjmiller5/tap"
      "asmvik/formulae"
      "ddev/ddev"
      "electrikmilk/cherri"
      "jellycuts/formulae"
      # yabai's formula tap — was untapped at some point but the formula is
      # still installed from it; nix-darwin re-taps it.
      "koekeishiya/formulae"
      "smudge/smudge"
      "steipete/tap"
      "supabase/tap"
    ];
    brews = [
      "automake"
      "base64"
      "bison"
      "bun"
      "chrome-cli"
      "chruby"
      "cloudflare-wrangler"
      "cmake"
      "create-dmg"
      "duti"
      "electrikmilk/cherri/cherri"
      "exiftool"
      "fastlane"
      "ffmpeg"
      "fswatch"
      "gdbm"
      "gogcli"
      "gsettings-desktop-schemas"
      "jupyterlab"
      # window manager — runs via the custom com.asmvik.yabai launchd agent
      "koekeishiya/formulae/yabai"
      "libffi"
      "libimobiledevice"
      "libomp"
      "libyaml"
      "lua@5.4"
      "luarocks"
      "mas"
      "mlton"
      "neovim"
      "node"
      "oci-cli"
      "openclaw-cli"
      "openssl@3"
      "perl"
      "pnpm"
      "python@3.10"
      "rbenv"
      "ruby-install"
      "skills"
      "smudge/smudge/nightlight"
      "supabase/tap/supabase"
      "terraform"
      "tree-sitter-cli"
      "vips"
      "vsce"
      "xcodegen"
      "yt-dlp"
    ];
    casks = [
      "1password"
      "1password-cli"
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
      "gcloud-cli"
      # TODO: uncomment after gemini-desktop's first release (v1.0.0) publishes
      # Casks/gemini.rb to alexjmiller5/tap — brew fails on a missing cask and
      # would break the switch. Replaces the old imperative install.sh install.
      # "gemini"
      "ghostty"
      "google-chrome"
      "hammerspoon"
      "karabiner-elements"
      "keyclu"
      "libreoffice"
      "mactex-no-gui"
      "notion"
      "notion-calendar"
      "notion-cli"
      # notunes comes from modules/notunes.nix
      "processing"
      "raycast"
      # TODO: uncomment after receptor's first release publishes
      # Casks/receptor.rb to alexjmiller5/tap — brew fails on a missing cask
      # and would break the switch. Replaces the DerivedData rm-cp-codesign flow.
      # "receptor"
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

    onActivation.cleanup = "zap";
  };
}
