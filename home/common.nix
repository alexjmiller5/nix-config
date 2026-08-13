{ username, ... }:

# Shared home-manager base for every host. The package list lives in
# cli-tools.nix (exported via homeModules); this file adds only the
# machine-identity bits external consumers set themselves.
{
  imports = [ ./git.nix ./scripts.nix ./cli-tools.nix ./mcp.nix ];

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";
}
