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

  # GUI apps that aren't packaged well in nixpkgs on macOS.
  # Requires Homebrew itself to be installed (see README manual steps).
  homebrew = {
    enable = true;
    casks = [
      "tailscale-app"
    ];
    onActivation.cleanup = "zap"; # remove anything not declared here
  };
}
