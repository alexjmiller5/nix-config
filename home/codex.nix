{ config, ... }:

# Codex CLI - the ChatGPT-subscription seat. Claude Code keeps the Claude
# seat: Anthropic prohibits third-party tools from using Free/Pro/Max OAuth
# tokens (enforced 2026-04-04), so only the OpenAI half is portable.
#
# Deliberately NOT set here:
#   - skills: Codex reads ~/.agents/skills natively, and agent-config-links.nix
#     already links the whole tree there. Setting programs.codex.skills would
#     duplicate it into a second, store-owned copy.
#   - context (~/.codex/AGENTS.md): an out-of-store symlink from
#     agent-config-links.nix instead, so edits to agent-config land without a
#     rebuild - same rule as Claude Code's CLAUDE.md. Leaving `context` at its
#     "" default makes the module skip writing that file at all, so there is
#     no collision with the symlink.
let
  hooksDir = "${config.home.homeDirectory}/.codex/hooks";
in
{
  programs.codex = {
    enable = true;

    # Merges programs.mcp.servers (mcp.nix) into config.toml's mcp_servers,
    # which is exactly the integration mcp.nix's header promises.
    enableMcpIntegration = true;

    settings = {
      # Mirrors Claude Code's bypassPermissions posture - Alex drives these
      # sessions interactively and reviews at the shell. "untrusted" is the
      # conservative dial if Codex ever runs somewhere less supervised.
      approval_policy = "on-request";
      sandbox_mode = "danger-full-access";

      # superpowers' subagent skills (dispatching-parallel-agents,
      # subagent-driven-development) need the multi-agent tools.
      # NB: superpowers' own Codex reference calls this `features.multi_agent`;
      # the current vendor config reference calls it `agents.enabled`. The
      # vendor reference wins - revisit if spawn_agent turns up missing.
      agents.enabled = true;
    };

    # AGENTS.md's deny-list, as closely as Codex's hook API allows. The script
    # is reached through the ~/.codex/hooks symlink so it stays editable in
    # agent-config without a rebuild.
    hooks.PreToolUse = [
      {
        matcher = "^Bash$";
        hooks = [
          {
            type = "command";
            command = "${hooksDir}/guard.sh";
            timeout = 10;
            statusMessage = "Checking command against deny-list";
          }
        ];
      }
    ];
  };
}
