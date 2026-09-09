{
  claude-plugin-ponytail,
  claude-plugin-superpowers,
  config,
  ...
}:

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

    # The MODULE only, not the binary: nixpkgs lags upstream badly (0.149.0 vs
    # 0.153.4 at the time of writing, and hooks only ship enabled by default
    # from 0.150.1). The cask tracks upstream, so codex comes from homebrew on
    # both hosts and `package = null` keeps this module doing what it is
    # actually here for - generating ~/.codex/hooks.json. Same reasoning as
    # claude-code@latest.
    package = null;

    # OFF deliberately: it would inject mcp_servers into `settings`, which
    # makes the module write ~/.codex/config.toml back into the store. Codex
    # must own that file (see below), so the MCP entry is seeded into the
    # agent-config copy instead.
    enableMcpIntegration = false;

    # Install the same portable plugin bundles Claude loads from the shared
    # skills tree. Their skills remain shared through ~/.agents/skills; native
    # Codex installation additionally activates plugin lifecycle hooks.
    plugins = [
      claude-plugin-ponytail
      claude-plugin-superpowers
    ];

    # settings deliberately EMPTY so home-manager writes no ~/.codex/config.toml.
    # Codex must be able to write that file: it persists hook trust and project
    # trust there, and a read-only store copy makes both fail with
    # `config/batchWrite failed ... failed to persist config.toml`. The file is
    # instead an out-of-store symlink into agent-config (see
    # agent-config-links.nix) - the same arrangement .claude/settings.json
    # already uses for a config its app writes to.
    #
    # The declarative settings, plugin enablement, MCP servers, and persisted
    # trust state live in that seeded file.
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
      {
        matcher = "^(exec|local_shell|exec_command|shell_command|shell|bash)$";
        hooks = [
          {
            type = "command";
            command = "${hooksDir}/op-item-conventions.sh";
            timeout = 10;
            statusMessage = "Loading 1Password conventions";
          }
        ];
      }
      {
        matcher = "^request_user_input$";
        hooks = [
          {
            type = "command";
            command = "${hooksDir}/moshi-hook.sh";
            async = true;
          }
        ];
      }
    ];

    hooks.PostToolUse = [
      {
        matcher = "^request_user_input$";
        hooks = [
          {
            type = "command";
            command = "${hooksDir}/moshi-hook.sh";
            async = true;
          }
        ];
      }
    ];

    hooks.SessionStart = [
      {
        hooks = [
          {
            type = "command";
            command = "${hooksDir}/moshi-hook.sh";
            async = true;
          }
        ];
      }
    ];

    hooks.PermissionRequest = [
      {
        hooks = [
          {
            type = "command";
            command = "${hooksDir}/moshi-hook.sh";
          }
        ];
      }
    ];

    hooks.SessionEnd = [
      {
        hooks = [
          {
            type = "command";
            command = "${hooksDir}/moshi-hook.sh";
          }
        ];
      }
    ];

    hooks.Stop = [
      {
        hooks = [
          {
            type = "command";
            command = "${hooksDir}/moshi-hook.sh";
            async = true;
          }
        ];
      }
    ];

    hooks.UserPromptSubmit = [
      {
        hooks = [
          {
            type = "command";
            command = "${hooksDir}/moshi-hook.sh";
            async = true;
          }
        ];
      }
    ];
  };
}
