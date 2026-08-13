# Canonical MCP server registry: programs.mcp writes ~/.config/mcp/mcp.json,
# and home-manager agent modules with enableMcpIntegration (codex, cursor,
# opencode, ...) merge it into their own config. Claude Code instead loads
# the same servers via agent-config's skills/mcp plugin (mcp@skills-dir) —
# its .mcp.json mirrors this list; keep the two in sync.
{
  programs.mcp = {
    enable = true;
    servers.nixos = {
      command = "nix";
      args = [ "run" "github:utensils/mcp-nixos" "--" ];
    };
  };
}
