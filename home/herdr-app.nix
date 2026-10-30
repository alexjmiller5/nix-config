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
  navigate = pkgs.writeShellApplication {
    name = "herdr-navigate";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../scripts/herdr-navigate.py} --herdr-app ${lib.getExe app} "$@"
    '';
  };
  settingsFile = pkgs.writeText "herdr-desktop-settings.json" (builtins.toJSON cfg.settings);
in
{
  options.programs.herdr-desktop = {
    enable = lib.mkEnableOption "the Herdr desktop core";
    app.enable = lib.mkEnableOption "the native Herdr window";
    settings = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      description = "Native settings merged at activation; other app preferences remain writable.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [
      core
    ]
    ++ lib.optionals cfg.app.enable [
      app
      navigate
    ];
    # Keep native preferences writable: only declared keys are enforced on switch.
    home.activation.herdrDesktopSettings = lib.mkIf cfg.app.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings=${lib.escapeShellArg "${config.xdg.configHome}/herdr-app/settings.json"}
        run mkdir -p "$(dirname "$settings")"
        if [ -z "''${DRY_RUN_CMD:-}" ]; then
          previous="$settings"
          [ -f "$previous" ] || previous=/dev/null
          temporary=$(mktemp "$settings.XXXXXX")
          ${pkgs.jq}/bin/jq -s 'reduce .[] as $item ({}; . * $item)' "$previous" ${settingsFile} > "$temporary"
          mv "$temporary" "$settings"
        fi
      ''
    );
    xdg.configFile."herdr-app/themes/catppuccin-latte.json" = lib.mkIf cfg.app.enable {
      source = ../dotfiles/herdr-app/catppuccin-latte.json;
    };
    xdg.configFile."herdr-app/themes/catppuccin-mocha.json" = lib.mkIf cfg.app.enable {
      source = ../dotfiles/herdr-app/catppuccin-mocha.json;
    };
    xdg.configFile."herdr-app/keys.json" = lib.mkIf cfg.app.enable {
      source = ../dotfiles/herdr-app/keys.json;
    };
  };
}
