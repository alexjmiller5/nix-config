# Agent tooling: node for agent-config hooks, `op` on PATH, and the shared
# initializer for independently enrolled operator credentials. Enrollment
# and rotation of the existing agent token file are separate from Nix
# bootstrap (see the host manuals). The shared base (common.nix) carries
# the op-authed CLI wrappers (op-wrappers.nix) and cli-tools.
#
# HOST-LAYER SIBLING (home-manager can't declare casks): the host's
# homebrew.casks needs `claude-code` and `notion-cli` (ntn — not in
# nixpkgs), and its allowUnfreePredicate must include "1password-cli".
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./agent-env.nix
    ./op-connect.nix
  ];

  options.aiAgent.withOp = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Install op (pkgs._1password-cli) on PATH. Disable where op is already provided some other way (e.g. a host's 1password-cli brew cask).";
  };

  config.home.packages = [
    pkgs.nodejs # agent-config hooks exec `node`; nix's shadows brew's (see zsh.nix)
    pkgs.skills # skills.sh agent-skills manager (was a laptop brew formula)
  ]
  ++ lib.optional config.aiAgent.withOp config.opConnect.cliPackage;

  # Claude Code never persists home-dir trust acceptance to disk (session-only
  # by design), so launching `claude` from ~ re-prompts on every start. Seed
  # the flag at each switch; everything else in ~/.claude.json stays app-owned
  # runtime state we never manage. A claude session running during the switch
  # may clobber the write on exit - it converges at the next switch.
  config.home.activation.claudeTrustHomeDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claudeJson="$HOME/.claude.json"
    [ -s "$claudeJson" ] || echo '{}' > "$claudeJson"
    if [ "$(${pkgs.jq}/bin/jq -r --arg d "$HOME" '.projects[$d].hasTrustDialogAccepted' "$claudeJson")" != "true" ]; then
      ${pkgs.jq}/bin/jq --arg d "$HOME" '.projects[$d].hasTrustDialogAccepted = true' "$claudeJson" \
        > "$claudeJson.tmp" && mv "$claudeJson.tmp" "$claudeJson" && chmod 600 "$claudeJson"
    fi
  '';
}
