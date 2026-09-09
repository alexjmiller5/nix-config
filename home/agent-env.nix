{ lib, ... }:
let
  initializer = builtins.readFile ./agent-detect.sh + "\n" + builtins.readFile ./agent-op-env.sh;
in
{
  # One entry point for shell startup and agent-specific lifecycle hooks.
  xdg.configFile."agent-shell/env.sh".text = initializer;
  programs.zsh.envExtra = lib.mkBefore initializer;
}
