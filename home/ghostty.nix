{ lib, pkgs, ... }:

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
      text = ''
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

        # Only herdr-window activates this table. Translate familiar macOS
        # shortcuts to Herdr's prefix keys; regular Ghostty surfaces retain
        # their native bindings. Cmd+Shift+W detaches without stopping agents.
        ''herdr/super+t=text:\x02c''
        ''herdr/super+shift+t=text:\x02t''
        ''herdr/super+shift+[=text:\x02p''
        ''herdr/super+shift+]=text:\x02n''
        ''herdr/super+w=text:\x02X''
        ''herdr/super+d=text:\x02v''
        ''herdr/super+shift+d=text:\x02-''
        ''herdr/super+[=text:\x02\x1b[Z''
        ''herdr/super+]=text:\x02\t''
        ''herdr/super+shift+enter=text:\x02z''
        ''herdr/super+shift+n=text:\x02N''
        ''herdr/super+p=text:\x02g''
        ''herdr/super+backslash=text:\x02b''
        ''herdr/super+alt+[=text:\x02\x10''
        ''herdr/super+alt+]=text:\x02\x0e''
        ''herdr/super+shift+w=text:\x02q''
        ''herdr/super+comma=text:\x02s''
      ]
      ++ lib.concatMap (n: [
        ''herdr/super+${n}=text:\x02${n}''
        ''herdr/super+digit_${n}=text:\x02${n}''
      ]) (map toString (lib.range 1 9));
    };
  };
}
