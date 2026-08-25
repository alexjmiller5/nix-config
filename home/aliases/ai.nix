# AI agent / Claude Code aliases. The op-* scripts resolve through
# ~/.claude/skills (a symlink into the agent-config repo).
{
  programs.zsh.shellAliases = {
    claude = "claude --model fable";
    cc = "claude"; # expands recursively, so it inherits the fable flag
    claude-max = "claude --model claude-fable --effort max";
    op-temp-sa = "~/.claude/skills/1password/scripts/op-temp-sa";
    # Load the temp-SA token minted by op-temp-sa into this shell (aliases run
    # in-shell, so the export sticks; token value never appears in transcripts)
    op-temp-sa-env = "export OP_SERVICE_ACCOUNT_TOKEN=$(security find-generic-password -s op-temp-sa -w)";
    op-project-bootstrap = "~/.claude/skills/1password/scripts/op-project-bootstrap";
    # Google consent flow for the gog wrapper (Alex-run; see the gog skill)
    gog-auth-bootstrap = "~/.claude/skills/gog/scripts/gog-auth-bootstrap";
  };
}
