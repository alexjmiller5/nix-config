# One registry, served through a native plugin shared by Claude and Codex.
# Codex's writable config keeps its own MCP servers and runtime trust state.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  json = pkgs.formats.json { };
  manifest = {
    name = "mcp";
    version = "1.0.0";
    description = "Shared declarative MCP servers";
    mcpServers = "./.mcp.json";
  };
  plugin =
    (pkgs.linkFarm "mcp" [
      {
        name = ".mcp.json";
        path =
          if config.programs.mcp.servers == { } then
            json.generate "mcp.json" { mcpServers = { }; }
          else
            config.xdg.configFile."mcp/mcp.json".source;
      }
      {
        name = ".claude-plugin/plugin.json";
        path = json.generate "claude-mcp-plugin.json" manifest;
      }
      {
        name = ".codex-plugin/plugin.json";
        path = json.generate "codex-mcp-plugin.json" manifest;
      }
    ])
    // {
      inherit (manifest) version;
    };
in
{
  programs.mcp = {
    enable = true;
    servers.nixos = {
      command = "nix";
      args = [
        "run"
        "github:utensils/mcp-nixos"
        "--"
      ];
    };
  };
  programs.codex.plugins = lib.mkIf config.programs.codex.enable [ plugin ];
  home.file.".config/agent-config/skills/mcp".source = plugin;
}
