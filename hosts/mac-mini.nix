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
  homebrew = {
    enable = true;
    casks = [ ];
    onActivation.cleanup = "zap"; # remove anything not declared here
  };
}
