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

    # OFF deliberately: it would inject mcp_servers into `settings`, which
    # makes the module write ~/.codex/config.toml back into the store. Codex
    # must own that file (see below), so the MCP entry is seeded into the
    # agent-config copy instead.
    enableMcpIntegration = false;

    # settings deliberately EMPTY so home-manager writes no ~/.codex/config.toml.
    # Codex must be able to write that file: it persists hook trust and project
    # trust there, and a read-only store copy makes both fail with
    # `config/batchWrite failed ... failed to persist config.toml`. The file is
    # instead an out-of-store symlink into agent-config (see
    # agent-config-links.nix) - the same arrangement .claude/settings.json
    # already uses for a config its app writes to.
    #
    # The declarative settings (approval_policy, sandbox_mode, agents.enabled,
    # mcp_servers, project trust) currently live in that seeded file. Once the
    # shape Codex writes for hook trust is known, they can move back into nix
    # with that shape baked in.
    settings = { };

    # AGENTS.md's deny-list, as closely as Codex's hook API allows. The script
    # is reached through the ~/.codex/hooks symlink so it stays editable in
    # agent-config without a rebuild.
    hooks.PreToolUse = [
      {
        # Codex names its shell tool differently across versions and between
        # exec and TUI ("^Bash$" from the docs example matches nothing here and
        # silently disables the guard - verified). Alternation covers every
        # name the 0.149 binary ships. The one that actually fires is `exec`:
        # 0.149 runs shell through Code Mode, where the model writes JS calling
        # tools.exec_command, so the command text is nested inside the JS -
        # which the guard still sees, because it scans every string leaf.
        # apply_patch is deliberately excluded:
        # it carries file CONTENT, which can legitimately contain a string like
        # "rm -rf /" and would false-positive.
        matcher = "^(exec|local_shell|exec_command|shell_command|shell|bash)$";
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
