{ pkgs, lib, username, ... }:

# Shared darwin host base — everything identical on every machine, injected
# for each host by mkHost (flake.nix). Host files carry only their diffs.
{
  system.stateVersion = 6;
  system.primaryUser = username;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # 1password-cli: op (home/ai-agent.nix). terraform: BSL, shared dev
  # toolbox. vscode-extension- prefix: licensed/platform-specific extensions
  # from pkgs.vscode-extensions (laptop's home/vscode.nix; a no-op on hosts
  # that don't import it).
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "1password-cli" "terraform" ]
    || lib.hasPrefix "vscode-extension-" (lib.getName pkg);

  # Both machines' nix installs (standalone installer on the laptop,
  # Determinate on the mini) manage the nix daemon themselves; nix-darwin
  # must not.
  nix.enable = false;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  environment.systemPackages = [ pkgs.git pkgs.just ];

  # Canonical flake location: darwin-rebuild and the infra aliases
  # (switch-*, valiases, …) resolve /etc/nix-darwin on either machine. A
  # string (not a path literal) keeps the symlink out-of-store; it points at
  # the machine's own working clone (companionRepos, machine-vault-git.nix).
  environment.etc."nix-darwin".source = "/Users/${username}/.config/nix-config";

  # Homebrew itself is installed/pinned by nix-homebrew (flake.nix). zap:
  # anything not in a host's declared lists is uninstalled at switch — the
  # lists ARE the machine.
  homebrew.enable = true;
  homebrew.onActivation.cleanup = "zap";
}
