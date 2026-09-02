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
    ./claude-plugins.nix
    ./machine-vault-git.nix
  ];

  # life-data: the admin hub token IS the agent estate's daily credential
  # (Alex's call 2026-09-02: agents are the sole CLI users, and any Mac
  # compromise reaches this item via the SA anyway - a separate scoped Macs
  # token added no real isolation). Scoped tokens exist for OTHER clients
  # (OwnTracks, notion-automations, future read-only consumers).
  lifeData.tokenOpRef = "op://4eeyrkqibibn7k4j6rz2fbzvxm/3qq7d6cltvwh3yzken2b46einm/credential";

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";
}
