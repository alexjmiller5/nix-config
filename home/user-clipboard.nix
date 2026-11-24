{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.user-clipboard;
in
{
  options.programs.user-clipboard = {
    enable = lib.mkEnableOption "a stdin command targeting the user's clipboard";
    targetHost = lib.mkOption {
      type = lib.types.str;
      default = "local";
      description = "Clipboard destination: local, or an SSH host alias.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "user-copy";
        runtimeInputs = [ pkgs.openssh ];
        text = ''
          export USER_CLIPBOARD_HOST="''${USER_CLIPBOARD_HOST:-${cfg.targetHost}}"
          ${builtins.readFile ./user-copy.sh}
        '';
      })
    ];
  };
}
