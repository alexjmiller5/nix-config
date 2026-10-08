{
  config,
  lib,
  pkgs,
  ...
}:

# Weekly Nix store cleanup for hosts whose installer, not nix-darwin, manages
# Nix (nix.enable = false). nix-darwin's nix.gc / nix.optimise assert
# nix.enable, so this is their equivalent: a root LaunchDaemon (same label,
# org.nixos.nix-gc) running the installed Nix's collect-garbage, then a store
# optimise (auto-optimise-store is unsafe on darwin). Old system generations
# are what pin the store, so `options` also bounds how far rollbacks reach.
let
  cfg = config.services.nix-gc;
  # The default profile holds the Nix that owns the store, whichever
  # multi-user installer put it there (Determinate or upstream).
  nixBin = "/nix/var/nix/profiles/default/bin";
  run = pkgs.writeShellScript "nix-gc" ''
    echo "== $(/bin/date)"
    /bin/df -h /nix
    ${nixBin}/nix-collect-garbage ${cfg.options}
    ${nixBin}/nix-store --optimise
    /bin/df -h /nix
  '';
in
{
  options.services.nix-gc = {
    enable = lib.mkEnableOption "weekly Nix garbage collection and store optimisation";
    options = lib.mkOption {
      type = lib.types.str;
      default = "--delete-older-than 14d";
      description = "Arguments to nix-collect-garbage.";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.nix-gc = {
      command = "${run}";
      serviceConfig = {
        StartCalendarInterval = lib.mkDefault [
          {
            Weekday = 7;
            Hour = 3;
            Minute = 15;
          }
        ];
        StandardOutPath = "/var/log/nix-gc.log";
        StandardErrorPath = "/var/log/nix-gc.log";
      };
    };
  };
}
