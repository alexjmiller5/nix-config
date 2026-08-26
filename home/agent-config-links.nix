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
  };
}
