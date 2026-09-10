{ lib, ... }:

# Shared terminal workspace settings for local and SSH sessions.
{
  programs.herdr = {
    enable = true;
    settings = lib.mkDefault {
      onboarding = false;
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
