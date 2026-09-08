# Restores moshi-hook's pairing state (the host id + host secret that
# `moshi-hook pair --store file` wrote) at every login from a 1Password item
# in this machine's vault, read via the machine SA - the same shape as
# op-agent-sa.nix. Pairing itself is a one-time token exchange with the Moshi
# phone app; keeping its output in 1P makes a rebuilt machine come back
# paired without re-running it. The daemon (brew formula + service, declared
# in the host) is kickstarted after the files land so it picks them up.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.moshiHook;
  restore = pkgs.writeShellScript "moshi-hook-restore" ''
    set -u
    read_field() {
      OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${cfg.tokenOpAuthFile})" \
        ${pkgs._1password-cli}/bin/op read "${cfg.itemOpRef}/$1" 2>/dev/null
    }
    for _ in 1 2 3 4 5; do
      secrets="$(read_field secrets_json)" && [ -n "$secrets" ] && break
      sleep 15
    done
    [ -n "''${secrets:-}" ] || { echo "op read failed after retries" >&2; exit 1; }
    store="$(read_field config_json)"
    umask 077
    mkdir -p "$HOME/.config/moshi"
    printf '%s' "$secrets" > "$HOME/.config/moshi/secrets.json"
    [ -n "$store" ] && printf '%s' "$store" > "$HOME/.config/moshi/config.json"
    # The brew service lands in the gui domain when started from a console
    # session and in the user domain when activation ran over ssh - try both.
    for d in gui user; do
      /bin/launchctl kickstart -k "$d/$(id -u)/${cfg.serviceLabel}" 2>/dev/null && break
    done
  '';
in
{
  options.moshiHook = {
    itemOpRef = lib.mkOption {
      type = lib.types.str;
      description = "op://<vault-id>/<item-id> (IDs, not names) of the item holding moshi-hook's secrets_json and config_json fields.";
    };
    tokenOpAuthFile = lib.mkOption {
      type = lib.types.path;
      description = "File holding the machine SA token that can read itemOpRef (the machine-sa agenix secret path).";
    };
    serviceLabel = lib.mkOption {
      type = lib.types.str;
      default = "homebrew.mxcl.moshi-hook";
      description = "launchd label of the moshi-hook daemon to kickstart after restoring the files.";
    };
  };

  config.launchd.agents.moshi-hook-restore = {
    enable = true;
    config = {
      Label = "com.alexmiller.moshi-hook-restore";
      ProgramArguments = [ "${restore}" ];
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/moshi-hook-restore.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/moshi-hook-restore.log";
    };
  };
}
