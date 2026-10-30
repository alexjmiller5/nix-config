{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.herdr-desktop;
  core = pkgs.callPackage ../pkgs/herdr-core.nix { };
  app = pkgs.callPackage ../pkgs/herdr-app.nix { };
in
{
  options.programs.herdr-desktop = {
    enable = lib.mkEnableOption "the Herdr desktop core";
    app.enable = lib.mkEnableOption "the native Herdr window";
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ core ] ++ lib.optional cfg.app.enable app;
    xdg.configFile."herdr-app/keys.json" = lib.mkIf cfg.app.enable {
      source = ../dotfiles/herdr-app/keys.json;
    };
  };
}
