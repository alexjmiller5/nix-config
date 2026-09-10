{
  config,
  lib,
  pkgs,
  ...
}:

# Shared terminal workspace settings for local and SSH sessions.
{
  # The bundled hooks use python3 to report session identity to Herdr's socket.
  home.packages = [ pkgs.python3 ];

  # Claude owns writable settings and hook files. Its idempotent installer
  # preserves other hooks and follows the companion-repo settings symlink.
  home.activation.herdrClaudeIntegration = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -d "$HOME/.claude" ]; then
      run ${lib.getExe config.programs.herdr.package} integration install claude
    fi
  '';

  home.file.".codex/herdr-agent-state.sh" = lib.mkIf config.programs.codex.enable {
    source = "${config.programs.herdr.package.src}/src/integration/assets/codex/herdr-agent-state.sh";
    executable = true;
  };
  programs.codex.hooks.SessionStart = lib.mkIf config.programs.codex.enable (
    lib.mkAfter [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "bash ${lib.escapeShellArg "${config.home.homeDirectory}/.codex/herdr-agent-state.sh"} session";
            timeout = 10;
          }
        ];
      }
    ]
  );

  programs.herdr = {
    enable = true;
    settings = lib.mkDefault {
      onboarding = false;
      session.resume_agents_on_restore = true;
      theme = {
        name = "catppuccin";
        auto_switch = true;
        light_name = "catppuccin-latte";
        dark_name = "catppuccin";
      };
      keys = {
        prefix = "ctrl+b";
        previous_agent = "prefix+ctrl+p";
        next_agent = "prefix+ctrl+n";
      };
      ui = {
        prompt_new_tab_name = false;
        agent_panel_sort = "spaces";
        show_agent_labels_on_pane_borders = true;
        sidebar.agents.rows = [
          [
            "state_icon"
            "workspace"
            "tab"
          ]
          [ "terminal_title_stripped" ]
          [ "agent" ]
        ];
      };
    };
  };
}
