# Agent tooling: node for agent-config hooks, `op` on PATH, and the shared
# initializer for independently enrolled operator credentials. Enrollment
# and rotation of the existing agent token file are separate from Nix
# bootstrap (see the host manuals). The shared base (common.nix) carries
# the op-authed CLI wrappers (op-wrappers.nix) and cli-tools.
#
# HOST-LAYER SIBLING (home-manager can't declare casks): the host's
# homebrew.casks needs `claude-code@latest` and `notion-cli` (ntn — not in
# nixpkgs), and its allowUnfreePredicate must include "1password-cli".
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../modules/manual-steps.nix
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

  # Human steps nix cannot do (rendered into MANUAL-<host>.md; verified by manual-check).
  config.manual.steps = {
    agent-operator-token = {
      title = "Enroll the AI Agent operator token";
      owner = "ai-agent";
      body = ''
        Agent tools use the independently provisioned AI Agent credential in the
        existing `~/.local/state/op/agent-sa-token` file (raw token only, owned by
        the local user, mode `0600`). Preserve it on an enrolled machine. Nix installs
        the initializer and consumers; it neither creates nor refreshes this file.
        Agent SSH, local Connect and launchd companion-repo sync consume it through
        their existing interfaces. No machine service account supplies or refreshes
        the agent token.

        For a replacement machine or deliberate rotation, use native 1Password
        desktop authentication to retrieve the authoritative AI Agent credential:
        vault `4eeyrkqibibn7k4j6rz2fbzvxm`, item `bktt2mfgbrbry53jrvitgxq45q`.
        The credential owner enrolls that token into the existing file with private
        permissions, using hidden input rather than a shell-history literal. This
        is separate from Nix bootstrap; do not recover from a machine-vault copy or
        substitute a machine SA. No additional credential cache is needed. After
        rotation, restart agent sessions and follow [Connect recovery](docs/op-connect.md).
        On the headless mini the `op-unlock` / `op-personal` user-session path is the way to retrieve it.
      '';
      verify = "test -s ~/.local/state/op/agent-sa-token";
      redo = "on a replacement machine or a deliberate rotation";
    };
    claude-code-login = {
      title = "Sign into Claude Code";
      owner = "claude-code";
      desktop = true;
      body = ''
        Sign into Claude Code (`claude` → `/login`) and, where installed, the Claude desktop app.
        Auth state lands in `~/.claude.json` and the login Keychain item "Claude Code-credentials" -
        deliberate imperative leftovers, never declared (same for `gcloud` / `op` credentials).
        Neither the operator token nor a Nix rebuild recreates it.
      '';
      verify = "security find-generic-password -s 'Claude Code-credentials' >/dev/null";
    };
  };

}
