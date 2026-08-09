{ config, osConfig, lib, pkgs, ... }:

# Mini home profile: shared base + the laptop's shell (zsh/starship/aliases,
# minus personal-infra aliases — those reference laptop-only workflows) + the
# agent-config fan-out so Claude Code on the mini gets the same skills,
# settings, AGENTS.md, and hooks.
#
# agent-config is a real git clone (cloned at activation, refreshed by a
# daily pull-only agent below) — no iCloud involved. The laptop stays the
# ONLY pusher (its sync agent commits+pushes); the mini never writes, so
# there's no push race. Clone/pull auth = `gh auth login` once (MANUAL §6).
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

  # gh stays for interactive CLI use (PRs etc.) — no longer the git
  # credential source.
  home.packages = [ pkgs.gh ];

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
}
