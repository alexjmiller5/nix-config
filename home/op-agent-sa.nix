# Writes the agent 1P service-account token (currently the claude-code SA —
# any future agent CLI shares it) to a 0600 file at every login, fetched from
# this machine's vault via the machine SA. Everything that auths agent shells
# reads that file (agent-op-env.sh, agent-config's claude/shell-init.sh), so
# this module is what makes a machine agent-authed
# declaratively — the only imperative state left is the machine-sa agenix
# secret. A file rather than the login Keychain: macOS locks the Keychain per
# login session, so ssh-descended shells (every agent shell on the headless
# mini) can never read a Keychain entry.
{ config, lib, pkgs, ... }:
let
  cfg = config.opAgentSa;
  loadToken = pkgs.writeShellScript "op-agent-sa-load" ''
    set -u
    # Retry: RunAtLoad can fire before the network is up. The token file
    # persists across boots, so a run that never succeeds only means a stale
    # (rarely-rotated) token, not a broken machine.
    for _ in 1 2 3 4 5; do
      token="$(OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${cfg.tokenOpAuthFile})" \
        ${pkgs._1password-cli}/bin/op read '${cfg.tokenOpRef}' 2>/dev/null)" && break
      sleep 15
    done
    [ -n "''${token:-}" ] || { echo "op read failed after retries" >&2; exit 1; }
    umask 077
    mkdir -p "$HOME/.local/state/op"
    printf '%s' "$token" > "$HOME/.local/state/op/agent-sa-token"
    # Retire the legacy Keychain copy (pre-file method) so no stale second
    # copy of the token lingers.
    /usr/bin/security delete-generic-password -s op-claude-sa >/dev/null 2>&1 || true
  '';
in
{
  options.opAgentSa = {
    tokenOpRef = lib.mkOption {
      type = lib.types.str;
      description = "op:// reference (IDs, not names) to the agent service-account token item in this machine's vault.";
    };
    tokenOpAuthFile = lib.mkOption {
      type = lib.types.path;
      description = "File holding the machine SA token that can read tokenOpRef (the machine-sa agenix secret path).";
    };
  };

  config.launchd.agents.op-agent-sa = {
    enable = true;
    config = {
      Label = "com.alexmiller.op-agent-sa";
      ProgramArguments = [ "${loadToken}" ];
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/op-agent-sa.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/op-agent-sa.log";
    };
  };
}
