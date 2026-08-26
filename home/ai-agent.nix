# AI-agent readiness as ONE check-off: import this module (plus set the
# opAgentSa refs it re-exports) and a machine's agent shells are fully
# capable — node for the agent-config hooks, `op` on PATH, and the agent SA
# token file refreshed at login. The shared base (common.nix) already
# carries the op-authed gh/modal wrappers and cli-tools.
#
# HOST-LAYER SIBLING (home-manager can't declare casks): the host's
# homebrew.casks needs `claude-code` and `notion-cli` (ntn — not in
# nixpkgs), and its allowUnfreePredicate must include "1password-cli".
{ config, lib, pkgs, ... }:
{
  imports = [ ./op-agent-sa.nix ];

  options.aiAgent.withOp = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Install op (pkgs._1password-cli) on PATH. Disable where the 1password-cli brew cask provides op with desktop-app integration (the laptop, until its TODO to test the nix op is done).";
  };

  config.home.packages =
    [ pkgs.nodejs ] # agent-config hooks exec `node`; nix's shadows brew's (see zsh.nix)
    ++ lib.optional config.aiAgent.withOp pkgs._1password-cli;
}
