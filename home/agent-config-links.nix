{ config, ... }:

# The agent-config fan-out, shared by every host: live symlinks from the
# agent homes into the agent-config working clone at ~/.config/agent-config
# (mkOutOfStoreSymlink: git-tracked but app-writable). ONE list — a fan-out
# file added here lands on both machines; adding it to a host file instead
# is exactly the drift the parity rule (AGENTS.md) forbids.
let
  agentConfig = "${config.home.homeDirectory}/.config/agent-config";
  mkLink = config.lib.file.mkOutOfStoreSymlink;
in
{
  home.file = {
    # skills served to BOTH the cross-agent standard location and Claude Code's
    ".agents/skills".source = mkLink "${agentConfig}/skills";
    ".claude/skills".source = mkLink "${agentConfig}/skills";
    ".claude/settings.json".source = mkLink "${agentConfig}/claude/settings.json";
    ".claude/shell-init.sh".source = mkLink "${agentConfig}/claude/shell-init.sh";
    ".claude/hooks".source = mkLink "${agentConfig}/claude/hooks";
    ".claude/CLAUDE.md".source = mkLink "${agentConfig}/AGENTS.md";
    ".claude/statusline.sh".source = mkLink "${agentConfig}/claude/statusline.sh";
    # Codex: AGENTS.md is the native instructions file, so it links straight
    # to the canonical one (no CLAUDE.md-style rename). hooks/ carries the
    # deny-list guard that home/codex.nix registers.
    ".codex/AGENTS.md".source = mkLink "${agentConfig}/AGENTS.md";
    ".codex/hooks".source = mkLink "${agentConfig}/codex/hooks";
    # Writable on purpose: Codex persists hook/project trust into config.toml,
    # and a store copy makes that fail. Its writes land as a git diff here.
    ".codex/config.toml".source = mkLink "${agentConfig}/codex/config.toml";
  };
}
