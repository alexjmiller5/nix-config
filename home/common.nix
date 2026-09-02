{ username, pkgs, ... }:

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
    ./claude-plugins.nix
    ./machine-vault-git.nix
  ];

  # life-data (module shipped by the app's flake). The admin hub token IS
  # the agent estate's daily credential (Alex's call 2026-09-02: agents are
  # the sole CLI users; a separate machine token added no real isolation -
  # the SA on these machines can read this item regardless). Scoped tokens
  # exist for OTHER clients (OwnTracks, notion-automations, ...).
  #
  # The two contexts authenticate independently (Alex's call 2026-09-02):
  # interactive `life` rides the shell's existing op auth; the daemon's
  # command is self-sufficient because launchd has no shell environment.
  lifeData =
    let
      hubTokenRef = "op://4eeyrkqibibn7k4j6rz2fbzvxm/3qq7d6cltvwh3yzken2b46einm/credential";
    in
    {
      enable = true;
      cli.tokenCommand = "op read '${hubTokenRef}'";
      watch = {
        tokenCommand = ''OP_SERVICE_ACCOUNT_TOKEN="$(cat "$HOME/.local/state/op/agent-sa-token")" op read '${hubTokenRef}' '';
        packages = [ pkgs._1password-cli ];
      };
    };

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";
}
