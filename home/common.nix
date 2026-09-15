{ username, pkgs, ... }:

# Shared home-manager base for every host. The package list lives in
# cli-tools.nix (exported via homeModules); this file adds only the
# machine-identity bits external consumers set themselves.
# machine-vault-git requires its options set per host; agent-config-links
# and op-wrappers are zero-config (op-wrappers needs nix-openclaw-tools in
# extraSpecialArgs).
{
  imports = [
    ./macos/finder.nix
    ./git.nix
    ./git-signing.nix
    ./scripts.nix
    ./cli-tools.nix
    ./mcp.nix
    ./op-wrappers.nix
    ./agent-config-links.nix
    ./claude-plugins.nix
    ./codex.nix
    ./machine-vault-git.nix
    ./people-sync-operator.nix
  ];

  opAuth.vaultId = "4eeyrkqibibn7k4j6rz2fbzvxm";

  # Life supplies the installed background runner and its CLI toggle.
  # Interactive agent auth remains separate; background credentials are
  # configured through `life background enable` on each device.
  lifeData = {
    enable = true;
  };

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";
}
