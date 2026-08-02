{ config, lib, ... }:

# Mini home profile: shared base + the laptop's shell (zsh/starship/aliases,
# minus personal-infra aliases — those reference laptop-only workflows) + the
# agent-config fan-out so Claude Code on the mini gets the same skills,
# settings, AGENTS.md, and hooks.
#
# The agent-config working clone reaches the mini via iCloud Desktop sync
# (~/Desktop is pinned "Keep Downloaded" there). Git sync runs ONLY on the
# laptop's launchd agent — two machines pushing the same iCloud-synced clone
# would race; the mini is a consumer.
let
  agentConfig = "${config.home.homeDirectory}/Desktop/coding/active-projects/agent-config";
  mkLink = path: config.lib.file.mkOutOfStoreSymlink path;
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

  home.file.".agents/skills".source = mkLink "${agentConfig}/skills";
  home.file.".claude/skills".source = mkLink "${agentConfig}/skills";
  home.file.".claude/settings.json".source = mkLink "${agentConfig}/claude/settings.json";
  home.file.".claude/shell-init.sh".source = mkLink "${agentConfig}/claude/shell-init.sh";
  home.file.".claude/hooks".source = mkLink "${agentConfig}/claude/hooks";
  home.file.".claude/CLAUDE.md".source = mkLink "${agentConfig}/AGENTS.md";
}
