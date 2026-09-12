{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.opAuth;
  settings = (pkgs.formats.json { }).generate "op-auth.json" {
    op = "${pkgs._1password-cli}/bin/op";
    inherit (cfg) vaultId serviceAccountTokenFile connect;
  };
  runner = "${pkgs.python3}/bin/python3 ${../scripts/op-auth.py} ${settings}";
  command =
    name: action:
    pkgs.writeShellScriptBin name ''
      ${builtins.readFile ./agent-detect.sh}
      export AGENT_OP_TOKEN_FILE="''${AGENT_OP_TOKEN_FILE:-${cfg.serviceAccountTokenFile}}"
      exec ${runner} ${action} "$@"
    '';
in
{
  options.opAuth = {
    vaultId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Operator SA vault ID; explicit requests for other vaults use user authentication.";
    };
    serviceAccountTokenFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/op/agent-sa-token";
      description = "Existing independently enrolled operator credential; never created by this module.";
    };
    connect = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = "Optional Connect routing configuration supplied by op-connect.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = pkgs.symlinkJoin {
        name = "op-auth";
        paths = [
          (command "op" "exec")
          (command "op-personal" "personal")
          (command "op-auth" "")
        ];
      };
      description = "op with automatic operator auth, plus op-personal and op-auth.";
    };
  };
}
