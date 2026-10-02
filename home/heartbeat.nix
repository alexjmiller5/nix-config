{ config, lib, ... }:

# Dead-man's switch: while this user session is up, ping a heartbeat URL
# (healthchecks.io style) every `interval` seconds; the monitoring service
# alerts when the pings stop. A user agent rather than a system daemon, so a
# reboot that never reaches the logged-in desktop also counts as down. The URL
# is a capability (anyone holding it can report the host alive), so it is read
# at run time from `urlFile`, outside this repo.
let
  cfg = config.services.heartbeat;
in
{
  options.services.heartbeat = {
    enable = lib.mkEnableOption "a periodic heartbeat ping";
    urlFile = lib.mkOption {
      type = lib.types.str;
      description = "File whose first line is the ping URL.";
    };
    interval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = "Seconds between pings.";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.agents.heartbeat = {
      enable = true;
      config = {
        Label = "com.alexmiller.heartbeat";
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''exec /usr/bin/curl -fsS -m 10 --retry 3 -o /dev/null "$(/usr/bin/head -n 1 "$0")"''
          cfg.urlFile
        ];
        StartInterval = cfg.interval;
        RunAtLoad = true;
        ProcessType = "Background";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/heartbeat.log";
      };
    };
  };
}
