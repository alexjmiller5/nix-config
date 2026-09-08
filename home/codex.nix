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

      # Trust is DECLARED, never persisted. config.toml is a read-only store
      # file, so Codex cannot write a trust decision at runtime - it fails with
      # `config/batchWrite failed`. Declaring the roots here is the right end
      # state anyway: same reason nothing else on these machines is configured
      # imperatively. A new root that needs trusting gets a line here, not a
      # click. Trust is per project root, so the roots are listed explicitly
      # rather than relying on inheritance from $HOME.
      projects = builtins.listToAttrs (
        map (dir: {
          name = "${config.home.homeDirectory}${dir}";
          value.trust_level = "trusted";
        }) [
          ""
          "/Desktop"
          "/Desktop/coding"
          "/Desktop/coding/active-projects"
          "/Desktop/coding/templates"
          "/Desktop/coding/misc-scripts"
          "/.config/nix-config"
          "/.config/agent-config"
          "/.config/agent-config-public"
        ]
      );

      # Same reasoning for hooks: Codex otherwise wants to persist a
      # `trusted_hash` for each hook into that same read-only file. There is no
      # untrusted-hook risk to gate here - the only hook is the deny-list guard
      # this module itself declares, out of the git-managed agent-config clone.
      bypass_hook_trust = true;

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
