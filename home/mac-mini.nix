{ config, osConfig, lib, pkgs, ... }:

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
  agentConfig = "${config.home.homeDirectory}/.config/agent-config";
  mkLink = path: config.lib.file.mkOutOfStoreSymlink path;
  agentConfigPull = pkgs.writeShellScript "agent-config-pull" ''
    set -euo pipefail
    export PATH="/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
    cd "${agentConfig}"
    git pull --ff-only --quiet origin main
  '';
in
{
  imports = [
    ./common.nix
    ./ai-agent.nix
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

  # Commit signing, same key as the laptop: the pub-key literal makes git
  # sign via ssh-keygen against the agent — which is the laptop's 1P agent,
  # forwarded (ForwardAgent yes on the mac-mini host blocks in nix-secrets;
  # Touch ID prompts land on the laptop). gpgsign stays OFF: detached
  # sessions (claude-rc, launchd) have no forwarded agent and auto-sign
  # would make their commits fail. Sign with `git commit -S` (or per-repo
  # `git config commit.gpgsign true`) when ssh'ed in.
  programs.git.settings = {
    user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKWqJ5X61r/CFl99qjU/rZyIB4DCQpVI+cF0y33WSSMC";
    gpg.format = "ssh";
  };

  # Inbound ssh from the laptop: public half of "Mac Mini SSH Key" (private
  # half in the 1Password Personal vault). Mini-only — nothing sshs into the
  # laptop. Written as a real file, not home.file — macOS sshd rejects an
  # authorized_keys symlinked into /nix/store.
  home.activation.installAuthorizedKeys = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    rm -f "$HOME/.ssh/authorized_keys"
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGVySz6jbVH+sW9q4+ru4CjHZjqmlMJ3p//0sLH1j8vH mac-mini' > "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
  '';

  # git-over-https auth, split by repo (mirrors macbook-air.nix):
  #  - agent-config: the machine-vault read-only fine-grained PAT, read at
  #    credential time via the agenix-decrypted machine SA. Bootstrap-only
  #    auth — it exists so the activation clone and daily pull work on a
  #    fresh machine before any login/agent state does. IDs, not names.
  #  - everything else: git.nix's `gh auth git-credential` default = the
  #    scripts.nix op-authed gh PATH wrapper — AI Agent vault PAT in agent
  #    shells (the agent's creds come from the AI Agent vault, never the
  #    machine vault); Alex's own ssh shells have no op auth source and
  #    stay unauthenticated.
  # useHttpPath makes git consult the repo-scoped helper key; the .git
  # suffix is REQUIRED — path matching is exact and the remote carries it.
  programs.git.settings.credential = {
    "https://github.com".useHttpPath = true;
    "https://github.com/alexjmiller5/agent-config.git".helper =
      "!${pkgs.writeShellScript "git-credential-machine-vault" ''
        [ "$1" = get ] || exit 0
        printf 'username=alexjmiller5\n'
        printf 'password=%s\n' "$(OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${osConfig.age.secrets.machine-sa.path})" ${pkgs._1password-cli}/bin/op read 'op://g532a3e4zyqqrc7b2v3lhv4zmy/k55oo3omg6yvrjmj7akdjakrwm/credential')"
      ''}";
  };

  # Agent SA token file (~/.local/state/op/agent-sa-token), refreshed at every
  # login from the machine vault via the machine SA — see home/op-agent-sa.nix.
  # This gives agent shells on the mini the same 1P access as on the laptop
  # (AI Agent vault + project vaults).
  opAgentSa = {
    tokenOpRef = "op://g532a3e4zyqqrc7b2v3lhv4zmy/qyi6fxsxyrog3mfpcbjzkjqvzi/credential";
    tokenOpAuthFile = osConfig.age.secrets.machine-sa.path;
  };

  # Remote-control Claude Code sessions, managed from an ssh shell (phone
  # terminal app / laptop). The session lives in detached /usr/bin/screen
  # from ~/Desktop (a trusted dir — trust for ~ itself never persists), so it
  # survives the ssh connection ending; interact via Remote Control in the
  # Claude app. Auth = claude's own login state; if a session comes up logged
  # out (keychain ACL breaks on cask upgrades), run claude over ssh and
  # /login once — creds then land in ~/.claude/.credentials.json. Stop is
  # pkill on claude, not `screen -X quit`: macOS screen orphans the child on
  # quit.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "claude-rc";
      text = ''
        pattern='claude --remote[-]control'
        case "''${1:-}" in
          start)
            /usr/bin/screen -wipe >/dev/null 2>&1 || true
            if /usr/bin/pgrep -f "$pattern" >/dev/null; then echo "already running"; exit 0; fi
            # shellcheck disable=SC2016 # $HOME expands in the child zsh, not here
            /usr/bin/screen -dmS claude-rc /bin/zsh -c 'cd "$HOME/Desktop" && exec /opt/homebrew/bin/claude --remote-control'
            echo "started - open Remote Control in the Claude app"
            ;;
          stop)
            /usr/bin/pkill -f "$pattern" && echo "stopped" || echo "no session running"
            ;;
          status)
            /usr/bin/pgrep -f "$pattern" >/dev/null && echo "running" || echo "not running"
            ;;
          *)
            echo "usage: claude-rc start|stop|status" >&2
            exit 1
            ;;
        esac
      '';
    })
  ];

  # Clone-if-missing at activation (mini analog of the laptop's companion-repos).
  # nix-config (public) + nix-secrets (private, via the machine-vault PAT —
  # the PAT must have read on it) make the mini self-sufficient for dev:
  # /etc/nix-darwin resolves (infra aliases), ssh host blocks resolve.
  home.activation.companionRepos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="/etc/profiles/per-user/${config.home.username}/bin:$PATH"
    companionClone() {
      [ -d "$2" ] || /usr/bin/git clone --quiet "https://github.com/alexjmiller5/$1.git" "$2" \
        || echo "companion-repos: clone of $1 failed — machine-sa decrypted? PAT scoped to it? redeploy" >&2
    }
    companionClone agent-config "${agentConfig}"
    companionClone nix-config "${config.home.homeDirectory}/.config/nix-config"
    companionClone nix-secrets "${config.home.homeDirectory}/.config/nix-secrets"
  '';

  # Daily pull, 30min after the laptop's 10:00 push window; RunAtLoad catches
  # up after downtime.
  launchd.agents.agent-config-pull = {
    enable = true;
    config = {
      Label = "com.alexmiller.agent-config-pull";
      ProgramArguments = [ "${agentConfigPull}" ];
      RunAtLoad = true;
      StartCalendarInterval = [ { Hour = 10; Minute = 30; } ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/agent-config-pull.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/agent-config-pull.log";
    };
  };

  home.file.".agents/skills".source = mkLink "${agentConfig}/skills";
  home.file.".claude/skills".source = mkLink "${agentConfig}/skills";
  home.file.".claude/settings.json".source = mkLink "${agentConfig}/claude/settings.json";
  home.file.".claude/shell-init.sh".source = mkLink "${agentConfig}/claude/shell-init.sh";
  home.file.".claude/hooks".source = mkLink "${agentConfig}/claude/hooks";
  home.file.".claude/CLAUDE.md".source = mkLink "${agentConfig}/AGENTS.md";
  home.file.".claude/statusline.sh".source = mkLink "${agentConfig}/claude/statusline.sh";
}
