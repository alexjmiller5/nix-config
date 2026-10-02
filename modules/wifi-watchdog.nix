{ lib, config, ... }:

# Wi-Fi watchdog for a Mac whose only uplink is Wi-Fi. A link can stay
# associated on either band while dropping most packets: Tailscale still
# lists the Mac online, but ssh and Herdr time out. A fresh association
# clears it. Every 2 minutes a root LaunchDaemon pings the default gateway
# over Wi-Fi and power-cycles Wi-Fi when it answers fewer than 15 of 20
# (see wifi-watchdog.sh); idle while ethernet carries the default route.
# Not for laptops: captive portals and travel networks would trip it.
let
  cfg = config.services.wifi-watchdog;
  script = "${./wifi-watchdog.sh}";
in
{
  options.services.wifi-watchdog.enable = lib.mkEnableOption "power-cycling Wi-Fi when the router stops answering over it";

  config = lib.mkIf cfg.enable {
    launchd.daemons.wifi-watchdog.serviceConfig = {
      # /bin/sh + wait4path: boot-time daemons load before the /nix volume
      # mounts (see modules/chrome-policy.nix).
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path '${script}' && exec /bin/sh '${script}'"
      ];
      # No RunAtLoad: right after boot Wi-Fi is still joining and looks dead.
      StartInterval = 120;
      StandardOutPath = "/var/log/wifi-watchdog.log";
      StandardErrorPath = "/var/log/wifi-watchdog.log";
    };
  };
}
