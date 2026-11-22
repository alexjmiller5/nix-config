{ config, lib, pkgs, ... }:
let
  cfg = config.programs.herdr-core-bridge;
  plugin = pkgs.callPackage ../pkgs/herdr-hc-attach.nix { };
  core = pkgs.callPackage ../pkgs/herdr-core.nix { };
  settings = pkgs.formats.toml { };
  bridgeConfig = config.programs.herdr.settings // {
    terminal = (config.programs.herdr.settings.terminal or { }) // {
      default_shell = "${plugin}/bin/hc-shell";
    };
  };
  launcher = pkgs.writeShellApplication {
    name = "herdr-core-tui";
    runtimeInputs = [ pkgs.nodejs core config.programs.herdr.package ];
    text = ''
      export HERDR_CONFIG_PATH="${config.xdg.configHome}/herdr/core-bridge.toml"
      export HC_BRIDGE_CORE_LAYOUT=1
      export HC_BRIDGE_TUI_SESSION=${lib.escapeShellArg cfg.session}
      export HERDR_SESSION=${lib.escapeShellArg cfg.session}
      export HC_BRIDGE_STATE_DIR="${config.xdg.stateHome}/herdr-core-bridge/${cfg.session}"
      export HC_BIN_PATH=${lib.getExe core}
      export HERDR_BIN_PATH=${lib.getExe config.programs.herdr.package}
      export HC_REAL_SHELL=${pkgs.zsh}/bin/zsh
      exec ${lib.getExe config.programs.herdr.package} --session "${cfg.session}" "$@"
    '';
  };
in {
  options.programs.herdr-core-bridge = {
    enable = lib.mkEnableOption "original Herdr TUI views of Core-owned terminals";
    session = lib.mkOption { type = lib.types.str; default = "core"; };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ launcher pkgs.nodejs ];
    xdg.configFile."herdr/core-bridge.toml".source = settings.generate "core-bridge.toml" bridgeConfig;
    programs.herdr-desktop.tuiPackage = launcher;
    home.activation.herdrCoreBridge = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${lib.getExe config.programs.herdr.package} plugin link ${plugin}
    '';
  };
}
