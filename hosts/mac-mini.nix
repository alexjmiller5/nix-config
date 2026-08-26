{ config, pkgs, lib, username, ... }:

{
  system.stateVersion = 6;
  system.primaryUser = username;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # 1password-cli: op, for agent shells (home/ai-agent.nix). terraform: BSL,
  # in the shared dev toolbox (home/dev-tools.nix).
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "1password-cli" "terraform" ];

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

  # Canonical flake location, same as the laptop: the infra aliases
  # (switch-mini, valiases, …) and darwin-rebuild resolve /etc/nix-darwin on
  # either machine. Points at the mini's own clone (companionRepos in
  # home/mac-mini.nix).
  environment.etc."nix-darwin".source = "/Users/${username}/.config/nix-config";

  # Headless tailscaled (no GUI app). One-time join after first switch:
  #   sudo tailscale up --auth-key=<oauth-minted key, tag:oauth-generated> --hostname=mac-mini
  services.tailscale.enable = true;

  # GUI apps that aren't packaged well in nixpkgs on macOS.
  # Homebrew itself is installed by nix-homebrew (see flake.nix).
  homebrew = {
    enable = true;
    casks = [
      "claude-code"
      # ntn — home/ai-agent.nix's host-layer sibling (not in nixpkgs).
      "notion-cli"
      # Browser for agent-driven web work (chrome-control / web-recon).
      "google-chrome"
    ];
    onActivation.cleanup = "zap"; # remove anything not declared here
  };

  # Weekly Apple-data snapshots (Sun 05:00 / 05:05). Each module installs a
  # signed .app + launchd agent; the one manual step per app is a Full Disk
  # Access grant (README §6). Output lands in iCloud-synced ~/Documents.
  services.screentime-backup = {
    enable = true;
    user = username;
  };
  services.callhistory-backup = {
    enable = true;
    user = username;
    # WhatsApp cask + keep-alive come from the module (its runtime dep for
    # third-party call durations). One-time QR link — README §6.
    installWhatsApp = true;
  };

  # The mini's ONE agenix secret: the mac-mini-machine 1P service-account
  # token (read-only on the "Mac Mini" vault). Every other secret — e.g. the
  # git PAT — lives in that vault, fetched at runtime via op read; see
  # secrets/secrets.nix.
  age.secrets.machine-sa = {
    file = ../secrets/machine-sa-mini.age;
    owner = username;
  };

}
