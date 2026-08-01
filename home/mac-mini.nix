{ config, ... }:

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

  home.file.".agents/skills".source = mkLink "${agentConfig}/skills";
  home.file.".claude/skills".source = mkLink "${agentConfig}/skills";
  home.file.".claude/settings.json".source = mkLink "${agentConfig}/claude/settings.json";
  home.file.".claude/shell-init.sh".source = mkLink "${agentConfig}/claude/shell-init.sh";
  home.file.".claude/hooks".source = mkLink "${agentConfig}/claude/hooks";
  home.file.".claude/CLAUDE.md".source = mkLink "${agentConfig}/AGENTS.md";
}
