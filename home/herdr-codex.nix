{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.herdrCodex;
  python = pkgs.python3.withPackages (p: [ p.websockets ]);
in
{
  options.programs.herdrCodex = {
    enable = lib.mkEnableOption "pane-local Codex identity registration and native core process ownership";
    executable = lib.mkOption {
      type = lib.types.str;
      default = lib.getExe pkgs.codex;
      description = "Underlying Codex executable, bypassing the PATH wrapper.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellScriptBin "codex" ''
        exec ${python}/bin/python3 ${../scripts/herdr-codex.py} --codex ${lib.escapeShellArg cfg.executable} -- "$@"
      '')
    ];
  };
}
