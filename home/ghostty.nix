{ ... }:

# Ghostty, via the native HM module (app itself stays the cask; the nixpkgs
# ghostty package is broken on darwin, hence package = null). Settings land
# in ~/.config/ghostty/config — on macOS Ghostty reads that alongside its
# Application Support path. Docs: https://ghostty.org/docs/config —
# `ghostty +show-config --default --docs` lists every option + default.
{
  programs.ghostty = {
    enable = true;
    package = null;

    settings = {
      # Theme follows macOS appearance (ghostty +list-themes for the full set)
      theme = "light:Catppuccin Latte,dark:Catppuccin Mocha";

      window-padding-x = 8;
      window-padding-y = 4;
      window-padding-balance = true;

      clipboard-paste-protection = false;
      shell-integration-features = "cursor,sudo,title,ssh-env,ssh-terminfo,path";

      # macOS-style cmd+arrow navigation: send real key sequences (Home / End /
      # Ctrl+Home / Ctrl+End) instead of the defaults, which nvim never sees
      # (ctrl-a/ctrl-e text + prompt jumping). zsh side is bound in zsh.nix.
      # Prompt jumping still available on cmd+shift+up/down (Ghostty default).
      # Opt+arrows: unbind Ghostty's esc:b/esc:f defaults so they encode as real
      # alt+arrows (CSI 1;3D/C), which nvim and the zsh bindkeys expect.
      keybind = [
        "alt+arrow_left=unbind"
        "alt+arrow_right=unbind"
        ''super+arrow_left=text:\x1b[H''
        ''super+arrow_right=text:\x1b[F''
        ''super+arrow_up=text:\x1b[1;5H''
        ''super+arrow_down=text:\x1b[1;5F''
      ];
    };
  };
}
