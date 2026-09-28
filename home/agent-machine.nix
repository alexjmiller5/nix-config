{ config, lib, ... }:

# Which capability sheet this machine's agents get. agent-config keeps one
# sheet per machine in machines/<profile>.md; the SessionStart hook
# (agent-config scripts/hooks/machine-context.py) prints whichever is linked
# here, so every session starts knowing what THIS machine can do and nothing
# about the other one. Out-of-store symlink: sheet edits land without a switch.
let
  cfg = config.agentMachine;
in
{
  options.agentMachine = {
    profile = lib.mkOption {
      type = lib.types.enum [
        "mini"
        "macbook"
      ];
      description = "Name of the capability sheet this machine's agent sessions load.";
    };
    sheetsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/agent-config/machines";
      description = "Directory holding <profile>.md capability sheets.";
    };
  };

  config = {
    xdg.configFile."agent-machine/AGENTS.md".source =
      config.lib.file.mkOutOfStoreSymlink "${cfg.sheetsDir}/${cfg.profile}.md";
    # For scripts that branch on the machine (hooks read the symlink instead).
    home.sessionVariables.AGENT_MACHINE = cfg.profile;
  };
}
