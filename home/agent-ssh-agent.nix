# A dedicated ssh-agent for agent shells, loaded at login with keys read from
# 1Password through the agent SA token file (op-agent-sa.nix). The private
# key exists only in the agent's memory - never on disk, never in the nix
# store - and no 1Password SSH-agent approval dialog is involved, so
# unattended agent sessions can ssh to hosts that trust these keys. Alex's
# own terminals keep using the 1Password SSH agent (ssh.nix); an ssh config
# Match on AGENT_SHELL selects this socket for agent shells only.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agentSshAgent;
  sock = "${config.home.homeDirectory}/.local/state/ssh/agent-ssh-agent.sock";
  serve = pkgs.writeShellScript "agent-ssh-agent" ''
    mkdir -p "$(dirname "${sock}")"
    chmod 700 "$(dirname "${sock}")"
    rm -f "${sock}"
    exec /usr/bin/ssh-agent -D -a "${sock}"
  '';
  load = pkgs.writeShellScript "agent-ssh-agent-load" ''
    set -u
    for _ in $(seq 1 30); do [ -S "${sock}" ] && break; sleep 2; done
    [ -S "${sock}" ] || { echo "agent socket never appeared" >&2; exit 1; }
    # Idempotent: runs at load and hourly (StartInterval) so a read that
    # failed at login - network down, 1Password account rate-limited - is
    # retried later without hammering the shared request budget.
    if SSH_AUTH_SOCK="${sock}" /usr/bin/ssh-add -l >/dev/null 2>&1; then exit 0; fi
    rc=0
    ${lib.concatMapStringsSep "\n" (ref: ''
      for _ in 1 2 3; do
        key="$(OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${cfg.tokenFile})" \
          ${pkgs._1password-cli}/bin/op read '${ref}?ssh-format=openssh')" && [ -n "$key" ] && break
        sleep 15
      done
      if [ -n "''${key:-}" ]; then
        printf '%s\n' "$key" | SSH_AUTH_SOCK="${sock}" /usr/bin/ssh-add - || rc=1
      else
        echo "op read failed for ${ref}" >&2; rc=1
      fi
      key=
    '') cfg.keyOpRefs}
    exit $rc
  '';
in
{
  options.agentSshAgent = {
    keyOpRefs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "op://<vault-id>/<item-id>/private key references (IDs, not names) of SSH Key items to load.";
    };
    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "File holding a 1Password service-account token that can read keyOpRefs (the agent SA token file).";
    };
    socket = lib.mkOption {
      type = lib.types.str;
      default = sock;
      readOnly = true;
      description = "Path of the agent's socket - point ssh's IdentityAgent at it.";
    };
  };

  config = {
    launchd.agents.agent-ssh-agent = {
      enable = true;
      config = {
        Label = "com.alexmiller.agent-ssh-agent";
        ProgramArguments = [ "${serve}" ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/agent-ssh-agent.log";
      };
    };
    launchd.agents.agent-ssh-agent-load = {
      enable = true;
      config = {
        Label = "com.alexmiller.agent-ssh-agent-load";
        ProgramArguments = [ "${load}" ];
        RunAtLoad = true;
        StartInterval = 3600;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/agent-ssh-agent.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/agent-ssh-agent.log";
      };
    };
  };
}
