{ pkgs, username, ... }:

{
  system.stateVersion = 6;
  system.primaryUser = username;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Determinate Nix manages the nix daemon itself; nix-darwin must not.
  nix.enable = false;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Headless box: never sleep, come back after power loss.
  power.sleep.computer = "never";
  power.sleep.display = "never";
  power.restartAfterPowerFailure = true;

  environment.systemPackages = with pkgs; [
    git
    just
  ];

  # Headless tailscaled (no GUI app). One-time join after first switch:
  #   sudo tailscale up --auth-key=<oauth-minted key, tag:oauth-generated> --hostname=mac-mini
  services.tailscale.enable = true;

  # GUI apps that aren't packaged well in nixpkgs on macOS.
  # Homebrew itself is installed by nix-homebrew (see flake.nix).
  # NB: the notion-finance-sync module adds the `google-chrome` cask; with
  # cleanup = "zap" that's fine — declared casks merge across modules.
  homebrew = {
    enable = true;
    casks = [ ];
    onActivation.cleanup = "zap"; # remove anything not declared here
  };

  # Daily bank -> Notion sync (module from the notion-finance-sync flake input).
  # Installs Chrome + the `op` CLI and a launchd user agent. One-time manual setup
  # (clone + uv sync, OP token in Keychain, Full Disk Access, first per-bank login)
  # is in that repo's README "Deploy to a Mac Mini with Nix".
  services.notion-finance-sync = {
    enable = true;
    user = username;
    checkoutDir = "/Users/${username}/Desktop/coding/active-projects/notion-finance-sync";
    hour = 3;
    minute = 30;
  };
}
