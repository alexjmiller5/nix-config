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
    ./life-data.nix
    ./mcp.nix
    ./op-wrappers.nix
    ./agent-config-links.nix
    ./machine-vault-git.nix
  ];

  # life-data hub (shared by both machines; IDs are non-secret, token in 1P)
  lifeData = {
    hubAccountId = "1e69de15e5dc3dddea6db7b3ae8087bc";
    hubDatabaseId = "a7a10931-e427-428e-8d0d-1e4024a3312b";
    tokenOpRef = "op://4eeyrkqibibn7k4j6rz2fbzvxm/mxxpo6neiz3grdyrjj7rv7nume/credential";
  };

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";
}
