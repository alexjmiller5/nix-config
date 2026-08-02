# AI agent / Claude Code aliases. The op-* scripts resolve through
# ~/.claude/skills (a symlink into the private-config repo).
{
  programs.zsh.shellAliases = {
    claude = "claude --model fable";
    claude-max = "claude --model claude-fable --effort max";
    op-temp-sa = "~/.claude/skills/1password/scripts/op-temp-sa";
    # Load the temp-SA token minted by op-temp-sa into this shell (aliases run
    # in-shell, so the export sticks; token value never appears in transcripts)
    op-temp-sa-env = "export OP_SERVICE_ACCOUNT_TOKEN=$(security find-generic-password -s op-temp-sa -w)";
    op-project-bootstrap = "~/.claude/skills/1password/scripts/op-project-bootstrap";
  };
}
