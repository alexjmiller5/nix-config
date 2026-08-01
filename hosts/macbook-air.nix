{ pkgs, username, ... }:

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

  # Tailscale runs via the GUI app (tailscale-app cask below), unlike the
  # mini's headless tailscaled.

  # Disable auto display brightness (laptop-only; written to /Library/Preferences
  # as root — takes effect after a restart).
  system.defaults.CustomSystemPreferences = {
    "/Library/Preferences/com.apple.iokit.AmbientLightSensor" = {
      "Automatic Display Enabled" = false;
    };
  };

  # Snapshot of the laptop's imperatively-installed brew state (refreshed
  # 2026-07-28 during Phase 0 reconcile), so the first switch changes nothing.
  homebrew = {
    enable = true;
    taps = [
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
      "gemini-cli"
      "gh"
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
      "bambu-studio"
      "betterdisplay"
      "binary-ninja-free"
      "burp-suite"
      "chatgpt"
      "claude"
      "claude-code"
      "codexbar"
      "discord"
      "docker-desktop"
      "dolphin"
      "duckduckgo"
      "figma"
      "gcloud-cli"
      "ghostty"
      "github"
      "google-chrome"
      "hammerspoon"
      "ipfs-desktop"
      "karabiner-elements"
      "keyclu"
      "legcord"
      "libreoffice"
      "mactex-no-gui"
      "mysqlworkbench"
      "notion"
      "notion-calendar"
      "notion-cli"
      # notunes comes from modules/notunes.nix
      "numi"
      "obsidian"
      "openclaw"
      "postman"
      "processing"
      "qbittorrent"
      "qflipper"
      "raspberry-pi-imager"
      "raycast"
      "repobar"
      "sf-symbols"
      "slack"
      "spotify"
      "tailscale-app"
      "temurin"
      "tor-browser"
      "visual-studio-code"
      "whatsapp"
      "wireshark-app"
      "xquartz"
      "yaak"
      "zoom"
    ];
    # App Store apps (enumerated via `mas list`, 2026-07-28). Requires being
    # signed in to the App Store; mas can't install un-purchased apps.
    masApps = {
      "Developer" = 640199958;
      "Flappy Golf 2" = 1154174205;
      "Flighty" = 1358823008;
      "hide.me" = 953040671;
      "Octagon" = 691956219;
      "ScreenZen" = 1541027222;
      "Telegram" = 747648890;
      "Xcode" = 497799835;
    };
    # Fully declarative since 2026-08-01: anything installed but undeclared
    # gets uninstalled on switch (dry-run reviewed before flipping — only
    # orphaned libevent + the nixpkgs-replaced zsh-autosuggestions).
    onActivation.cleanup = "zap";
  };
}
