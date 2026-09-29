# Agents on an Xcode 27 host: Apple's Xcode MCP server (`xcrun mcpbridge`,
# reached through the headless `xcrun mcp-server` daemon that
# modules/xcode-agent.nix enables) and Apple's own agent skills, served from
# the export a human step produces (below).
#
# Import this only where Xcode 27 lives. On Xcode 26.x `mcpbridge` needs a
# windowed Xcode and there is no `xcrun agent`, so the laptop (Xcode 26.3
# until its macOS passes 26.2) does not import it yet.
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
    description = "Apple's Xcode agent skills, exported from the installed Xcode";
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
  imports = [ ../modules/manual-steps.nix ];

  programs.mcp.servers.xcode = {
    command = "xcrun";
    args = [ "mcpbridge" ];
  };

  home.file.".config/agent-config/skills/apple".source = plugin;

  # The export is a human step: `xcrun agent skills export` runs inside a
  # windowed Xcode on an unlocked desktop. From activation it hung at the
  # lock screen and left that Xcode running, and a running windowed Xcode
  # shadows the headless server: every MCP call then waits forever.
  manual.steps.apple-skills-export = {
    title = "Export Apple's agent skills from Xcode";
    owner = "xcode-agent";
    desktop = true;
    body = ''
      From a terminal on the unlocked desktop (Screen Sharing):

      ```bash
      xcrun agent skills export --output-dir ${skillsDir} --replace-existing
      osascript -e 'tell application "Xcode" to quit'
      ```

      Quit Xcode afterwards: while a windowed Xcode runs, `xcrun mcpbridge`
      talks to it instead of the headless server and agents hang.
    '';
    verify = "test -f ${skillsDir}/swiftui-specialist/SKILL.md";
    redo = "after every major Xcode update";
  };
}
