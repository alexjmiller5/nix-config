{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:

# Mini home profile: full dev parity with the laptop at the shell level —
# shared base + dev toolbox + the laptop's shell (zsh/starship/all alias
# categories) + ssh config + the agent-config fan-out so Claude Code on the
# mini gets the same skills, settings, AGENTS.md, and hooks. What stays
# laptop-only is the GUI layer (casks, dock, Chrome policy, hammerspoon,
# karabiner, VS Code) and the Apple build chain.
#
# agent-config is a real git clone (cloned at activation, refreshed by a
# daily pull-only agent below) — no iCloud involved. For the agent-config
# SYNC, the laptop stays the only pusher (its sync agent commits+pushes;
# the mini's sync never writes, so there's no push race) — but the mini is
# otherwise a full dev machine: general git pushes work and auth via the
# AI Agent vault PAT (gh wrapper), same as the laptop. Sync clone/pull auth
# = the repo-scoped machine-vault PAT credential helper below.
let
  agentConfigPull = pkgs.writeShellScript "agent-config-pull" ''
    set -euo pipefail
    export PATH="/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
    cd "$HOME/.config/agent-config"
    git pull --ff-only --quiet origin main
    # PUBLIC sibling clone (generic skills reached via committed symlinks
    # in agent-config/skills) - same pull-only refresh, anonymous auth.
    cd "$HOME/.config/agent-config-public"
    git pull --ff-only --quiet origin main
  '';
in
{
  imports = [
    ./common.nix
    ./ai-agent.nix
    ./moshi-hook.nix
    ./dev-tools.nix
    ./zsh.nix
    ./aliases/dev.nix
    ./aliases/ai.nix
    ./aliases/infra.nix
    ./ssh.nix
  ];

  # No 1P desktop app here — outbound ssh uses the default agent socket
  # (SSH_AUTH_SOCK), so a laptop agent forwarded over `ssh -A` serves the
  # keys the nix-secrets host blocks select. ssh.nix's 1P IdentityAgent
  # default would otherwise point at a socket that never exists.
  programs.ssh.settings."*".IdentityAgent = lib.mkForce "SSH_AUTH_SOCK";

  # Inbound ssh from the laptop: public halves of "Mac Mini SSH Key" (Alex's
  # terminals, private half in the 1Password Personal vault) and "AI Agent
  # Mac Mini SSH Key" (laptop agent shells, private half in the AI Agent
  # vault, served by home/agent-ssh-agent.nix). Mini-only — nothing sshs
  # into the laptop. Written as a real file, not home.file — macOS sshd
  # rejects an authorized_keys symlinked into /nix/store.
  home.activation.installAuthorizedKeys = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    rm -f "$HOME/.ssh/authorized_keys"
    {
      echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGVySz6jbVH+sW9q4+ru4CjHZjqmlMJ3p//0sLH1j8vH mac-mini'
      echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKVhSzQV7atZiw0i4o51bUPL3BzzZB2DLreuQoS+/Nz0 ai-agent-mac-mini'
    } > "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
  '';

  # Machine-vault git bootstrap (home/machine-vault-git.nix): the mini's PAT
  # is read-only on these repos — its sync only pulls. nix-config (public) +
  # nix-secrets make the mini self-sufficient for dev: /etc/nix-darwin
  # resolves (infra aliases), ssh host blocks resolve.
  machineVaultGit = {
    patOpRef = "op://g532a3e4zyqqrc7b2v3lhv4zmy/k55oo3omg6yvrjmj7akdjakrwm/credential";
    patAuthFile = osConfig.age.secrets.machine-sa.path;
    patRepos = [
      "alexjmiller5/agent-config"
      "alexjmiller5/nix-secrets"
    ];
    companionRepos = {
      "alexjmiller5/agent-config" = "${config.home.homeDirectory}/.config/agent-config";
      # PUBLIC sibling of agent-config (generic skills); anonymous clone/pull.
      "alexjmiller5/agent-config-public" = "${config.home.homeDirectory}/.config/agent-config-public";
      "alexjmiller5/nix-config" = "${config.home.homeDirectory}/.config/nix-config";
      "alexjmiller5/nix-secrets" = "${config.home.homeDirectory}/.config/nix-secrets";
    };
  };

  # Agent SA token file (~/.local/state/op/agent-sa-token), refreshed at every
  # login from the machine vault via the machine SA — see home/op-agent-sa.nix.
  # This gives agent shells on the mini the same 1P access as on the laptop
  # (AI Agent vault + project vaults).
  opAgentSa = {
    tokenOpRef = "op://g532a3e4zyqqrc7b2v3lhv4zmy/qyi6fxsxyrog3mfpcbjzkjqvzi/credential";
    tokenOpAuthFile = osConfig.age.secrets.machine-sa.path;
  };

  # moshi-hook pairing state (host id + secret) restored from the machine
  # vault at login - see home/moshi-hook.nix. Item: "Mac Mini Moshi Host Secret".
  moshiHook = {
    itemOpRef = "op://g532a3e4zyqqrc7b2v3lhv4zmy/guamxzzrlh46slq7xqfkbrl4by";
    tokenOpAuthFile = osConfig.age.secrets.machine-sa.path;
  };

  home.packages = [
    # Time-boxed Personal-vault access for agents on the headless mini. No
    # desktop app here, so Touch ID isn't an option: Alex runs `op-unlock`
    # from an ssh shell (phone terminal), types his 1Password account password,
    # and the resulting CLI session token is written to
    # ~/.local/state/op/personal-session (0600). The op-personal shell
    # function (home/zsh.nix) uses that token when the file exists, so agent
    # sessions read Personal exactly as they do on the laptop. A transient
    # launchd keepalive touches the session every 20 min (op sessions die
    # after 30 idle minutes) and after N hours (default 6) signs out
    # server-side and deletes the file. No secrets ever touch disk - only the
    # session token, which the sign-out invalidates. One-time prerequisite:
    # `op account add` on this machine (MANUAL-mac-mini.md §6).
    (pkgs.writeShellApplication {
      name = "op-unlock";
      runtimeInputs = [ pkgs._1password-cli ];
      text = ''
        state="$HOME/.local/state/op"
        f="$state/personal-session"
        case "''${1:-}" in
          keepalive) # internal: op-unlock keepalive <hours>
            end=$(( $(date +%s) + ''${2:-6} * 3600 ))
            while [ "$(date +%s)" -lt "$end" ] && [ -r "$f" ]; do
              sleep 1200
              op --session "$(cat "$f")" whoami >/dev/null 2>&1 || break
            done
            if [ -r "$f" ]; then op --session "$(cat "$f")" signout >/dev/null 2>&1 || true; fi
            rm -f "$f"
            ;;
          lock)
            /bin/launchctl remove com.alexmiller.op-unlock >/dev/null 2>&1 || true
            if [ -r "$f" ]; then
              op --session "$(cat "$f")" signout >/dev/null 2>&1 || true
              rm -f "$f"; echo "locked"
            else
              echo "already locked"
            fi
            ;;
          status)
            if [ -r "$f" ] && op --session "$(cat "$f")" whoami >/dev/null 2>&1; then
              echo "unlocked (session file $(stat -f %Sm "$f"))"
            else
              rm -f "$f"; echo "locked"
            fi
            ;;
          ""|[0-9]*)
            hours="''${1:-6}"
            umask 077; mkdir -p "$state"
            /bin/launchctl remove com.alexmiller.op-unlock >/dev/null 2>&1 || true
            # Prompts for the account password on this tty; --raw prints the token.
            env -u OP_SERVICE_ACCOUNT_TOKEN op signin --raw > "$f.tmp"
            mv "$f.tmp" "$f"
            # Transient launchd job, not screen/nohup: macOS kills those with
            # the ssh session that started them (the phone terminal closing).
            /bin/launchctl submit -l com.alexmiller.op-unlock -- "$0" keepalive "$hours"
            echo "unlocked for ''${hours}h - agents can read Personal via op-personal; op-unlock lock to end early"
            ;;
          *)
            echo "usage: op-unlock [hours=6] | lock | status" >&2
            exit 1
            ;;
        esac
      '';
    })
  ];

  # Daily pull, 30min after the laptop's 10:00 push window; RunAtLoad catches
  # up after downtime.
  launchd.agents.agent-config-pull = {
    enable = true;
    config = {
      Label = "com.alexmiller.agent-config-pull";
      ProgramArguments = [ "${agentConfigPull}" ];
      RunAtLoad = true;
      StartCalendarInterval = [
        {
          Hour = 10;
          Minute = 30;
        }
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/agent-config-pull.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/agent-config-pull.log";
    };
  };
}
