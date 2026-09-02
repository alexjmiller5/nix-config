{
  config,
  lib,
  pkgs,
  life-data,
  ...
}:

# life-data — schema-agnostic personal data store (local-first SQLite + `life`
# CLI). Exported via homeModules; consumers pass `life-data` through
# extraSpecialArgs and set lifeData.tokenOpRef.
#
# This module knows only what a USER of the app knows: where to get the
# credential, and (optionally) which hub to talk to. No account ids, no
# database ids, no bucket names — the service owns all of that. Backups run
# server-side on the hub's own cron; the only client-side job is continuous
# sync. The database itself lives in ~/.local/share/life-data, never in the
# store and never in a repo.
let
  cfg = config.lifeData;
  pkg = life-data.packages.${pkgs.stdenv.hostPlatform.system}.default;
  watch = pkgs.writeShellApplication {
    name = "life-watch";
    runtimeInputs = [
      pkg
      pkgs._1password-cli
    ];
    text = ''
      OP_SERVICE_ACCOUNT_TOKEN="$(cat "$HOME/.local/state/op/agent-sa-token")"
      export OP_SERVICE_ACCOUNT_TOKEN
      life init >/dev/null
      exec life watch
    '';
  };
in
{
  options.lifeData = {
    tokenOpRef = lib.mkOption {
      type = lib.types.str;
      description = "op:// reference (IDs, not names) to the hub API token.";
    };
    hubUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Hub to sync with. Null uses the CLI's built-in default (the hosted service); set it to self-host.";
    };
  };

  config = {
    # duckdb: `life archive query --raw` shells out to it for analytical
    # queries over the raw stream objects
    home.packages = [
      pkg
      pkgs.duckdb
    ];

    # Read-only by design: this file is machine config, and the app keeps all
    # of its mutable state in the database (_sync_state), never here.
    xdg.dataFile."life-data/config.json".text = builtins.toJSON (
      { token_cmd = "op read '${cfg.tokenOpRef}'"; }
      // lib.optionalAttrs (cfg.hubUrl != null) { hub_url = cfg.hubUrl; }
    );

    # Continuous sync: pushes local writes within ~1s, polls for remote
    # changes. KeepAlive restarts it if it ever dies.
    launchd.agents.life-watch = {
      enable = true;
      config = {
        Label = "com.alexmiller.life-watch";
        ProgramArguments = [ "${watch}/bin/life-watch" ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/life-watch.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/life-watch.log";
      };
    };
  };
}
