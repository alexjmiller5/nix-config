{
  config,
  lib,
  pkgs,
  life-data,
  ...
}:

# life-data — schema-agnostic personal data store (local-first SQLite +
# `life` CLI). Exported via homeModules; consumers must pass `life-data`
# through extraSpecialArgs and set the lifeData.* options. The module
# installs the CLI, declares the hub/backup config (non-secret IDs; the
# token stays in 1Password, fetched by token_cmd at runtime), and runs a
# weekly sync+backup launchd agent authed via the op-agent-sa token file.
# The data itself lives in ~/.local/share/life-data — never in the store.
let
  cfg = config.lifeData;
  pkg = life-data.packages.${pkgs.stdenv.hostPlatform.system}.default;
  weekly = pkgs.writeShellApplication {
    name = "life-weekly";
    runtimeInputs = [
      pkg
      pkgs._1password-cli
    ];
    text = ''
      OP_SERVICE_ACCOUNT_TOKEN="$(cat "$HOME/.local/state/op/agent-sa-token")"
      export OP_SERVICE_ACCOUNT_TOKEN
      life init >/dev/null
      life sync
      life backup
    '';
  };
in
{
  options.lifeData = {
    hubAccountId = lib.mkOption {
      type = lib.types.str;
      description = "Cloudflare account id hosting the D1 hub.";
    };
    hubDatabaseId = lib.mkOption {
      type = lib.types.str;
      description = "D1 database id of the hub.";
    };
    tokenOpRef = lib.mkOption {
      type = lib.types.str;
      description = "op:// reference (IDs, not names) to the Cloudflare API token.";
    };
    backupBucket = lib.mkOption {
      type = lib.types.str;
      default = "life-data-backups";
      description = "R2 bucket receiving `life backup` SQL dumps.";
    };
  };

  config = {
    home.packages = [ pkg ];

    xdg.dataFile."life-data/config.json".text = builtins.toJSON {
      hub = {
        account_id = cfg.hubAccountId;
        database_id = cfg.hubDatabaseId;
        token_cmd = "op read '${cfg.tokenOpRef}'";
      };
      backup = {
        bucket = cfg.backupBucket;
        prefix = "backups/";
      };
    };

    launchd.agents.life-weekly = {
      enable = true;
      config = {
        Label = "com.alexmiller.life-weekly";
        ProgramArguments = [ "${weekly}/bin/life-weekly" ];
        StartCalendarInterval = [
          {
            Weekday = 1;
            Hour = 10;
            Minute = 30;
          }
        ];
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/life-weekly.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/life-weekly.log";
      };
    };
  };
}
