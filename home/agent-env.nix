{ config, lib, ... }:
let
  initializer =
    "export AGENT_OP_TOKEN_FILE=\"\${AGENT_OP_TOKEN_FILE:-${config.opAuth.serviceAccountTokenFile}}\"\n"
    + builtins.readFile ./agent-detect.sh
    + "\n"
    + builtins.readFile ./agent-op-env.sh;
in
{
  imports = [ ./op-auth.nix ];
  # One entry point for shell startup and agent-specific lifecycle hooks.
  xdg.configFile."agent-shell/env.sh".text = initializer;
  programs.zsh.envExtra = lib.mkBefore initializer;
}
