{ username, ... }:

# Shared home-manager base for every host. The package list lives in
# cli-tools.nix (exported via homeModules); this file adds only the
# machine-identity bits external consumers set themselves.
# machine-vault-git requires its options set per host; agent-config-links
# and op-wrappers are zero-config (op-wrappers needs nix-openclaw-tools in
# extraSpecialArgs).
{
  imports = [
    ./git.nix
    ./scripts.nix
    ./cli-tools.nix
    ./mcp.nix
    ./op-wrappers.nix
    ./agent-config-links.nix
    ./machine-vault-git.nix
  ];

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";
}
