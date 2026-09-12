{ pkgs, ... }:

# Ghostty, via the native HM module (app itself stays the cask; the nixpkgs
# ghostty package is broken on darwin, hence package = null). Settings land
# in ~/.config/ghostty/config — on macOS Ghostty reads that alongside its
# Application Support path. Docs: https://ghostty.org/docs/config —
# `ghostty +show-config --default --docs` lists every option + default.
{
  imports = [ ./herdr.nix ];

  home.packages = [
    (pkgs.writeShellApplication {
      name = "herdr-window";
      # The macOS shortcuts live in Hammerspoon (herdrHotkeys.lua), scoped to
      # the windows it is told about - a Ghostty key table would work too, but
      # an active one paints an indicator pill that cannot be turned off.
      text = ''
        # Claim the next new Ghostty window for Hammerspoon's hotkeys. A
        # sentinel file, not an `hs -c` call: opening a terminal must not wait
        # on (or fail with) Hammerspoon's IPC port.
        state="''${XDG_STATE_HOME:-$HOME/.local/state}/herdr-window"
        mkdir -p "$state"
        : > "$state/pending"
        exec /usr/bin/osascript ${../scripts/herdr-window.applescript} "$PWD" "${pkgs.herdr}/bin/herdr"
      '';
    })
  ];

  programs.ghostty = {
    enable = true;
    package = null;

    settings = {
      # Theme follows macOS appearance (ghostty +list-themes for the full set)
      theme = "light:Catppuccin Latte,dark:Catppuccin Mocha";

      window-padding-x = 8;
      window-padding-y = 4;
      window-padding-balance = true;

      copy-on-select = "clipboard";
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
