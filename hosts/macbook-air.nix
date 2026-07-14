{ pkgs, username, ... }:

# MacBook Air. NOT DEPLOYED YET — staged for the eventual full nix-darwin
# migration of the laptop. Mirrors the mini minus its headless-server bits
# (never-sleep power settings, headless tailscaled) and its data-collection
# services (screentime/callhistory/finance-sync — the flake imports those
# modules for every host, but only mac-mini.nix enables them).
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

  # Snapshot of the laptop's imperatively-installed brew state (2026-07-13),
  # so the first switch changes nothing.
  homebrew = {
    enable = true;
    taps = [
      "asmvik/formulae"
      "ddev/ddev"
      "electrikmilk/cherri"
      "jellycuts/formulae"
      "smudge/smudge"
      "steipete/tap"
      "supabase/tap"
    ];
    brews = [
      "act"
      "automake"
      "base64"
      "bat"
      "bison"
      "bun"
      "chrome-cli"
      "chruby"
      "cloudflare-wrangler"
      "cmake"
      "create-dmg"
      "d2"
      "duti"
      "exiftool"
      "fastlane"
      "ffmpeg"
      "fswatch"
      "fzf"
      "gemini-cli"
      "gh"
      "git-filter-repo"
      "gitleaks"
      "gogcli"
      "gsettings-desktop-schemas"
      "jupyterlab"
      "just"
      "libffi"
      "libimobiledevice"
      "lua@5.4"
      "luarocks"
      "mlton"
      "oci-cli"
      "openclaw-cli"
      "perl"
      "pnpm"
      "python@3.10"
      "rbenv"
      "ruby-install"
      "sevenzip"
      "shellcheck"
      "skills"
      "sshpass"
      "terraform"
      "tree"
      "uv"
      "vips"
      "vsce"
      "yq"
      "yt-dlp"
      "zsh-autosuggestions"
    ];
    casks = [
      "1password"
      "1password-cli"
      "alt-tab"
      "claude"
      "claude-code"
      "codexbar"
      "discord"
      "docker-desktop"
      "figma"
      "gcloud-cli"
      "ghostty"
      "github"
      "keyclu"
      "mactex-no-gui"
      "notion"
      "notion-calendar"
      "notion-cli"
      # notunes + spotify come from modules/notunes.nix
      "obsidian"
      "openclaw"
      "postman"
      "raycast"
      "repobar"
      "sf-symbols"
      "slack"
      "tailscale-app"
      "temurin"
      "tor-browser"
      "visual-studio-code"
      "wireshark-app"
      "xquartz"
    ];
    # The mini uses "zap" (uninstall anything undeclared). Flip this to "zap"
    # only after a first successful switch confirms the lists above are
    # complete — zap on a stale list uninstalls whatever it's missing.
    onActivation.cleanup = "none";
  };
}
