# Pick up another Herdr machine's Claude sessions here when that machine is
# down. Herdr itself has no cross-machine failover (each server owns its panes)
# and Claude Code has no session sync, so a launchd job mirrors the source
# machine's transcripts and Herdr session.json here every minute, and
# `herdr-takeover` recreates each tab in this machine's Herdr with
# `claude --resume`. When the source comes back it resumes the same sessions
# itself, so close one of the two forks.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.herdrTakeover;
  stateDir = "${config.xdg.stateHome}/herdr-takeover";
  sync = pkgs.writeShellApplication {
    name = "herdr-takeover-sync";
    runtimeInputs = [ pkgs.rsync ];
    text = ''
      host=${lib.escapeShellArg cfg.host}
      ssh=(/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5)
      # The source being unreachable is the case this mirror exists for: no noise.
      "''${ssh[@]}" "$host" true 2>/dev/null || exit 0
      mkdir -p ${stateDir}
      # -u keeps a session already taken over here (newer than the source copy).
      # memory/ dirs are agent-config symlinks on every machine: never mirrored.
      rsync -au -e "''${ssh[*]}" --exclude '/*/memory' "$host:.claude/projects/" "$HOME/.claude/projects/"
      rsync -au -e "''${ssh[*]}" "$host:.config/herdr/session.json" ${stateDir}/session.json
    '';
  };
  takeover = pkgs.writeShellApplication {
    name = "herdr-takeover";
    runtimeInputs = [
      pkgs.python3
      config.programs.herdr.package
    ];
    text = ''exec python3 ${../scripts/herdr-takeover.py} --session-file ${stateDir}/session.json "$@"'';
  };
in
{
  options.herdrTakeover = {
    enable = lib.mkEnableOption "mirroring another Herdr machine's Claude sessions for takeover";
    host = lib.mkOption {
      type = lib.types.str;
      description = "ssh destination of the Herdr machine whose Claude sessions are mirrored here.";
    };
    interval = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Seconds between mirror runs.";
    };
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment for the mirror job, e.g. whatever selects an unattended ssh identity.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      sync
      takeover
    ];
    launchd.agents.herdr-takeover-sync = {
      enable = true;
      config = {
        Label = "com.alexmiller.herdr-takeover-sync";
        EnvironmentVariables = cfg.environment;
        ProgramArguments = [ (lib.getExe sync) ];
        RunAtLoad = true;
        StartInterval = cfg.interval;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/herdr-takeover-sync.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/herdr-takeover-sync.log";
      };
    };
  };
}
