# Agents on an Xcode 27 host: Apple's Xcode MCP server (`xcrun mcpbridge`,
# reached through the headless `xcrun mcp-server` daemon that
# modules/xcode-agent.nix enables) and Apple's own agent skills, materialized
# from the installed Xcode at every switch.
#
# Import this only where Xcode 27 lives. On Xcode 26.x `mcpbridge` needs a
# windowed Xcode and there is no `xcrun agent`, so the laptop (Xcode 26.3
# until its macOS passes 26.2) does not import it yet.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  json = pkgs.formats.json { };
  skillsDir = "${config.home.homeDirectory}/.local/state/apple-skills";
  manifest = {
    name = "apple";
    version = "1.0.0";
    description = "Apple's Xcode agent skills, materialized from the installed Xcode";
  };
  piSkillDescriptions = {
    app-intents-specialist = "Use when writing, reviewing, refactoring or debugging App Intents, entities, queries, enums, parameters, dependencies, results, donation, localization, shortcut phrases, URL representations, widget or control configuration. Apple's authoritative evergreen guidance. For iOS 26/27 API adoption, use app-intents-whats-new-27.";
    app-intents-whats-new-27 = "Use when adopting or migrating iOS 26/27 App Intents APIs or asking what changed: execution modes, foreground continuation, cancellation, long-running intents, choice prompts, interactive snippets, Visual Intelligence, onscreen entities, Spotlight indexing, computed/deferred properties, schemas, relevant entities, cross-device ownership, system shortcuts, AppIntentsTesting, entity collections and union values. Covers corresponding macOS/watchOS/tvOS/visionOS releases.";
  };
  # Same shape as home/mcp.nix: a plugin dir Claude/Codex auto-load from the
  # shared skills dir as `apple@skills-dir`; `skills` is a state symlink that
  # activation points at the materialized plugin.
  plugin = pkgs.linkFarm "apple-skills-plugin" [
    {
      name = ".claude-plugin/plugin.json";
      path = json.generate "apple-plugin.json" manifest;
    }
    {
      name = ".codex-plugin/plugin.json";
      path = json.generate "apple-codex-plugin.json" manifest;
    }
    {
      name = "skills";
      path = skillsDir;
    }
  ];
in
{
  programs.mcp.servers.xcode = {
    command = "xcrun";
    args = [ "mcpbridge" ];
  };

  # A store symlink inside the agent-config clone: its target changes on every
  # rebuild, so agent-config's .gitignore lists it with the other plugin links.
  home.file.".config/agent-config/skills/apple".source = plugin;

  # Manage the directory as one link so activation replaces an existing skills
  # symlink instead of following it and writing into a shared source directory.
  home.file."${config.programs.pi-coding-agent.configDir}/skills" =
    lib.mkIf config.programs.pi-coding-agent.enable
      {
        source = pkgs.linkFarm "pi-apple-skills" (
          lib.mapAttrsToList (name: description: {
            name = "${name}/SKILL.md";
            # Pi caps discovery descriptions at 1024 characters. Load Apple's complete
            # current guidance and references without modifying Xcode's plugin files.
            path = pkgs.writeText "${name}-SKILL.md" ''
              ---
              name: ${name}
              description: ${builtins.toJSON description}
              ---

              Read `${skillsDir}/${name}/SKILL.md` before doing this task.
              Follow the complete instructions there and resolve every relative
              reference from `${skillsDir}/${name}/`.
            '';
          }) piSkillDescriptions
        );
      };

  # `xcrun agent plugin path` materializes Apple's packaged plugin (skills in
  # the open Agent Skills format) under ~/Library/Developer/Xcode, keyed by
  # the Xcode build, without launching Xcode. Re-pointing the state symlink
  # at every switch keeps the skills in step with the installed Xcode.
  # Never `xcrun agent skills export` here: it launches a windowed Xcode,
  # which hangs on a locked display and shadows the headless MCP server.
  # ponytail: the Claude format serves both agents through the shared skills
  # dir (three skills differ slightly in the Codex format); materialize the
  # codex format into programs.codex.plugins if that ever matters.
  home.activation.linkAppleSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    major=$(/usr/bin/xcodebuild -version 2>/dev/null | /usr/bin/awk 'NR==1{split($2,v,"."); print v[1]+0}')
    if [ "''${major:-0}" -ge 27 ]; then
      if plugin=$(${pkgs.coreutils}/bin/timeout 60 /usr/bin/xcrun agent plugin path --plugin-format claude 2>/dev/null) \
        && [ -d "$plugin/skills" ]; then
        [ -d ${lib.escapeShellArg skillsDir} ] && [ ! -L ${lib.escapeShellArg skillsDir} ] \
          && /bin/rmdir ${lib.escapeShellArg skillsDir} 2>/dev/null || true
        /bin/mkdir -p "$(/usr/bin/dirname ${lib.escapeShellArg skillsDir})"
        /bin/ln -sfn "$plugin/skills" ${lib.escapeShellArg skillsDir}
      else
        echo "apple-agent: xcrun agent plugin path failed; Apple's skills keep their previous version"
      fi
    else
      echo "apple-agent: Xcode 27 not installed, skipping Apple's skills"
    fi
  '';
}
