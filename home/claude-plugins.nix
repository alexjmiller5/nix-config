{
  claude-plugins-official,
  claude-plugin-superpowers,
  claude-plugin-ponytail,
  ...
}:

# Claude Code plugins, declared instead of installed.
#
# `claude plugin install` is an imperative install with no lockfile, and
# settings.json's `enabledPlugins` only says which plugins to LOAD - it never
# fetches them, so a fresh machine restored from the config repos got zero
# plugins. Instead these are pinned flake inputs linked in place: Claude Code
# auto-discovers any directory under ~/.claude/skills carrying
# .claude-plugin/plugin.json and loads it as <name>@skills-dir - no install,
# no marketplace, no network at activation, and no enabledPlugins entry
# needed. Versions ride the weekly input bump like every other input.
#
# They land in the agent-config skills dir (git-ignored there) rather than in
# ~/.claude directly, because that one directory is fanned out to BOTH agent
# homes - ~/.claude/skills and ~/.agents/skills - so the skills these plugins
# carry stay available to any agent, not just Claude. Both machines: the mini
# runs agents too, and agent-config-links.nix is already a both-machines list.
{
  home.file = {
    ".config/agent-config/skills/frontend-design".source =
      "${claude-plugins-official}/plugins/frontend-design";
    ".config/agent-config/skills/skill-creator".source =
      "${claude-plugins-official}/plugins/skill-creator";
    ".config/agent-config/skills/superpowers".source = claude-plugin-superpowers;
    ".config/agent-config/skills/ponytail".source = claude-plugin-ponytail;
  };
}
