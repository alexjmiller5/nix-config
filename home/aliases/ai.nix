# AI agent / Claude Code aliases. The op-* scripts resolve through
# ~/.claude/skills (a symlink into the private agent-config repo).
{
  programs.zsh.shellAliases = {
    claude = "claude --model fable";
    claude-max = "claude --model claude-fable --effort max";
    op-temp-sa = "~/.claude/skills/1password/scripts/op-temp-sa";
    op-project-bootstrap = "~/.claude/skills/1password/scripts/op-project-bootstrap";
  };
}
