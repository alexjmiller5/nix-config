{
  config,
  lib,
  pkgs,
  ...
}:

let
  undoClose = pkgs.callPackage ../pkgs/herdr-undo-close.nix { };
  autoTitle = pkgs.callPackage ../pkgs/herdr-auto-title.nix { };
in
# Shared terminal workspace settings for local and SSH sessions.
{
  # The bundled hooks use python3 to report session identity to Herdr's socket.
  home.packages = [ pkgs.python3 ];

  home.activation.herdrUndoClose = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe config.programs.herdr.package} plugin link ${undoClose}
  '';
  home.activation.herdrAutoTitle = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe config.programs.herdr.package} plugin link ${autoTitle}
  '';
  home.file."herdr-auto-title-config" = {
    target =
      if pkgs.stdenv.hostPlatform.isDarwin then
        "Library/Application Support/herdr-auto-title/config.env"
      else
        "${config.xdg.configHome}/herdr-auto-title/config.env";
    text = ''
      HERDR_AUTO_TITLE_AGENT_NAME=false
    '';
  };
  xdg.configFile."herdr/plugins/config/undo-close/config.json".text = builtins.toJSON {
    undo_panes = false;
  };

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
      # Every prefix key Hammerspoon's herdrHotkeys.lua types is pinned here:
      # it presses ctrl+b then these keys, so a changed Herdr default must not
      # silently move a shortcut. `herdr config check` validates the pairs.
      keys = {
        prefix = "ctrl+b";
        new_tab = "prefix+c";
        next_tab = "prefix+n";
        previous_tab = "prefix+p";
        switch_tab = "prefix+1";
        split_vertical = "prefix+v";
        split_horizontal = "prefix+minus";
        cycle_pane_next = "prefix+tab";
        cycle_pane_previous = "prefix+shift+tab";
        zoom = "prefix+z";
        new_workspace = "prefix+shift+n";
        goto = "prefix+g";
        toggle_sidebar = "prefix+b";
        detach = "prefix+q";
        settings = "prefix+s";
        previous_agent = "prefix+ctrl+p";
        next_agent = "prefix+ctrl+n";
        close_tab = [ ];
        command = [
          {
            key = "prefix+shift+x";
            type = "plugin_action";
            command = "undo-close.close-tab";
            description = "Close tab and save agent sessions";
          }
          {
            key = "prefix+t";
            type = "plugin_action";
            command = "undo-close.reopen-last";
            description = "Reopen closed tab";
          }
        ];
      };
      ui = {
        copy_on_select = true;
        toast.clipboard.enabled = false;
        prompt_new_tab_name = false;
        agent_panel_sort = "spaces";
        show_agent_labels_on_pane_borders = true;
        # Fill behind the focused sidebar row. A palette name (not a hex) so it
        # tracks the catppuccin light/dark switch; cyan reads too faint to spot.
        accent = "magenta";
        # Herdr mutes every row after the first; dim = false opts out without
        # pinning a color, so the catppuccin light/dark switch still applies.
        sidebar.agents.rows = [
          [
            "state_icon"
            {
              token = "workspace";
              dim = false;
            }
            {
              token = "tab";
              dim = false;
            }
          ]
          [
            {
              token = "terminal_title_stripped";
              dim = false;
            }
          ]
          [
            {
              token = "agent";
              dim = false;
            }
          ]
        ];
      };
    };
  };
}
