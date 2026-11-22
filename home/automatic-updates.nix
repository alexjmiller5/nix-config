{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.automatic-updates;
  env = {
    PATH = "/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    AGENT_SHELL = "repo-sync";
  };
  job = name: args: minute: {
    enable = true;
    config = {
      Label = "local.${name}";
      ProgramArguments = args;
      EnvironmentVariables = env;
      StartCalendarInterval = [
        {
          Hour = 10;
          Minute = minute;
        }
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/${name}.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/${name}.log";
    };
  };
in
{
  options.services.automatic-updates = {
    enable = lib.mkEnableOption "automatic Homebrew upgrades and weekly verified Nix activation";
    host = lib.mkOption {
      type = lib.types.str;
      description = "Darwin flake configuration name.";
    };
    repository = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.configHome}/nix-config";
    };
  };
  config = lib.mkIf cfg.enable {
    launchd.agents.package-updates = job "package-updates" [
      "${pkgs.python3}/bin/python3"
      "${../scripts/package-updates.py}"
      "/opt/homebrew/bin/brew"
    ] 15;
    launchd.agents.system-updates = job "system-updates" [
      "${pkgs.python3}/bin/python3"
      "${../scripts/system-updates.py}"
      "--repo"
      cfg.repository
      "--host"
      cfg.host
      "--state"
      "${config.xdg.stateHome}/system-updates"
    ] 30;
  };
}
