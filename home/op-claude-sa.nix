# Loads the claude-code 1P service-account token into the login Keychain
# (service "op-claude-sa") at every login, fetched from this machine's vault
# via the machine SA. Everything that auths agent shells reads that Keychain
# entry (zsh.nix $AGENT_SHELL block, agent-op-env.sh, the gh/modal wrappers),
# so this module is what makes a machine "Claude-authed" declaratively — the
# only imperative state left is the machine-sa agenix secret.
{ config, lib, pkgs, ... }:
let
  cfg = config.opClaudeSa;
  loadToken = pkgs.writeShellScript "op-claude-sa-load" ''
    set -u
    # Retry: RunAtLoad can fire before the network is up. The Keychain entry
    # persists across boots, so a run that never succeeds only means a stale
    # (rarely-rotated) token, not a broken machine.
    for _ in 1 2 3 4 5; do
      token="$(OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${cfg.tokenOpAuthFile})" \
        ${pkgs._1password-cli}/bin/op read '${cfg.tokenOpRef}' 2>/dev/null)" && break
      sleep 15
    done
    [ -n "''${token:-}" ] || { echo "op read failed after retries" >&2; exit 1; }
    /usr/bin/security add-generic-password -U -a "$USER" -s op-claude-sa -w "$token"
  '';
in
{
  options.opClaudeSa = {
    tokenOpRef = lib.mkOption {
      type = lib.types.str;
      description = "op:// reference (IDs, not names) to the claude-code SA token item in this machine's vault.";
    };
    tokenOpAuthFile = lib.mkOption {
      type = lib.types.path;
      description = "File holding the machine SA token that can read tokenOpRef (the machine-sa agenix secret path).";
    };
  };

  config.launchd.agents.op-claude-sa = {
    enable = true;
    config = {
      Label = "com.alexmiller.op-claude-sa";
      ProgramArguments = [ "${loadToken}" ];
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/op-claude-sa.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/op-claude-sa.log";
    };
  };
}
