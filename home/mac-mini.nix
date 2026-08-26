{ config, osConfig, lib, pkgs, ... }:

# Mini home profile: shared base + the laptop's shell (zsh/starship/aliases,
# minus personal-infra aliases — those reference laptop-only workflows) + the
# agent-config fan-out so Claude Code on the mini gets the same skills,
# settings, AGENTS.md, and hooks.
#
# agent-config is a real git clone (cloned at activation, refreshed by a
# daily pull-only agent below) — no iCloud involved. The laptop stays the
# ONLY pusher (its sync agent commits+pushes); the mini never writes, so
# there's no push race. Clone/pull auth = the machine-vault PAT credential
# helper below — no gh login involved.
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
    ./zsh.nix
    ./aliases/dev.nix
    ./aliases/ai.nix
  ];

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

  # git-over-https auth (overrides git.nix's gh mkDefault): the read-only
  # fine-grained PAT is read from the "Mac Mini" 1P vault at credential time,
  # authenticated by the agenix-decrypted machine SA token. IDs, not names.
  # No gh auth involved — nothing to log in at bootstrap.
  programs.git.settings.credential."https://github.com".helper =
    "!${pkgs.writeShellScript "git-credential-machine-vault" ''
      [ "$1" = get ] || exit 0
      printf 'username=alexjmiller5\n'
      printf 'password=%s\n' "$(OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${osConfig.age.secrets.machine-sa.path})" ${pkgs._1password-cli}/bin/op read 'op://g532a3e4zyqqrc7b2v3lhv4zmy/k55oo3omg6yvrjmj7akdjakrwm/credential')"
    ''}";

  # gh (for interactive CLI use — no longer the git credential source) comes
  # from the scripts.nix op-authed wrapper; no bare pkgs.gh here. Agent-context
  # gh calls auth via the agent SA token file (refreshed below); calls in
  # Alex's own ssh shells have no op auth source and stay unauthenticated.

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
  home.activation.companionRepos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="/etc/profiles/per-user/${config.home.username}/bin:$PATH"
    [ -d "${agentConfig}" ] || /usr/bin/git clone --quiet "https://github.com/alexjmiller5/agent-config.git" "${agentConfig}" \
      || echo "companion-repos: agent-config clone failed — machine-sa secret decrypted? op read reachable? redeploy" >&2
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
