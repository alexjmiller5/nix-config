# AI agent / Claude Code aliases. The op-* scripts resolve through
# ~/.claude/skills (a symlink into the agent-config repo).
{
  programs.zsh.shellAliases = {
    # claude-fable-5-1 needs Claude Code >= 2.1.251 (older versions 400 on it);
    # the hosts declare claude-code@latest, which satisfies that.
    claude = "claude --model claude-fable-5-1";
    cc = "claude"; # expands recursively, so it inherits the model flag
    # `command` keeps the claude alias from expanding here too — without it
    # this recursively picks up the model flag and passes --model twice.
    # Model name must match the `claude` alias exactly.
    claude-max = "command claude --model claude-fable-5-1 --effort max";
    op-temp-sa = "~/.claude/skills/1password/scripts/op-temp-sa";
    # Load the temp-SA token minted by op-temp-sa into this shell (aliases run
    # in-shell, so the export sticks; token value never appears in transcripts)
    op-temp-sa-env = "export OP_SERVICE_ACCOUNT_TOKEN=$(security find-generic-password -s op-temp-sa -w)";
    op-project-bootstrap = "~/.claude/skills/1password/scripts/op-project-bootstrap";
    # Google consent flow for the gog wrapper (Alex-run; see the gog skill)
    gog-auth-bootstrap = "~/.claude/skills/gog/scripts/gog-auth-bootstrap";
  };
}
