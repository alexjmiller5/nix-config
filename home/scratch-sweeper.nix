{
  config,
  lib,
  pkgs,
  ...
}:

# Daily sweep of scratch that never cleans itself up: Chrome's per-launch
# app-bundle clones (left behind by every killed Chrome) and Xcode
# DerivedData entries untouched for `derivedDataMaxAgeDays`. Selection rules
# live in scratch-sweeper.py; run it with --dry-run to preview.
let
  cfg = config.services.scratch-sweeper;
in
{
  options.services.scratch-sweeper = {
    enable = lib.mkEnableOption "a daily sweep of Chrome bundle clones and stale Xcode DerivedData";
    derivedDataMaxAgeDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 14;
      description = "Remove a DerivedData entry once nothing in it changed for this many days.";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.agents.scratch-sweeper = {
      enable = true;
      config = {
        Label = "com.alexmiller.scratch-sweeper";
        ProgramArguments = [
          (lib.getExe pkgs.python3)
          "${./scratch-sweeper.py}"
          "--derived-data-days"
          (toString cfg.derivedDataMaxAgeDays)
        ];
        StartCalendarInterval = [
          {
            Hour = 4;
            Minute = 30;
          }
        ];
        ProcessType = "Background";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/scratch-sweeper.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/scratch-sweeper.log";
      };
    };
  };
}
