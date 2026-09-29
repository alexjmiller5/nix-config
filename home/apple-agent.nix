# Agents on an Xcode 27 host: Apple's Xcode MCP server (`xcrun mcpbridge`,
# reached through the headless `xcrun mcp-server` daemon that
# modules/xcode-agent.nix enables) and Apple's own agent skills, re-exported
# on every switch so they always match the installed Xcode.
#
# Import this only where Xcode 27 lives. On Xcode 26.x `mcpbridge` needs a
# windowed Xcode and there is no `xcrun agent`, so the laptop (Xcode 26.3
# until its macOS passes 26.2) does not import it yet. On a host without
# Xcode 27 the activation skips with one line and never fails the switch.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  json = pkgs.formats.json { };
  skillsDir = "${config.home.homeDirectory}/.local/state/apple-skills";
  manifest = {
    name = "apple";
    version = "1.0.0";
    description = "Apple's Xcode agent skills, re-exported at every switch";
  };
  # Same shape as home/mcp.nix: a plugin dir Claude/Codex auto-load from the
  # shared skills dir as `apple@skills-dir`; `skills` points at the export.
  plugin = pkgs.linkFarm "apple-skills-plugin" [
    {
      name = ".claude-plugin/plugin.json";
      path = json.generate "apple-plugin.json" manifest;
    }
    {
      name = ".codex-plugin/plugin.json";
      path = json.generate "apple-codex-plugin.json" manifest;
    }
    {
      name = "skills";
      path = skillsDir;
    }
  ];
in
{
  programs.mcp.servers.xcode = {
    command = "xcrun";
    args = [ "mcpbridge" ];
  };

  home.file.".config/agent-config/skills/apple".source = plugin;

  home.activation.exportAppleSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    major=$(/usr/bin/xcodebuild -version 2>/dev/null | /usr/bin/awk 'NR==1{split($2,v,"."); print v[1]+0}')
    if [ "''${major:-0}" -ge 27 ]; then
      /bin/mkdir -p ${lib.escapeShellArg skillsDir}
      # Bounded: on a host where mcpbridge waits for an Xcode approval the export
      # would otherwise hang the whole switch.
      if ! ${pkgs.coreutils}/bin/timeout 120 /usr/bin/xcrun agent skills export --output-dir ${lib.escapeShellArg skillsDir} >/dev/null 2>&1; then
        echo "apple-agent: xcrun agent skills export failed or timed out; run it by hand (see MANUAL)"
      fi
    else
      echo "apple-agent: Xcode 27 not installed, skipping skills export"
    fi
  '';
}
