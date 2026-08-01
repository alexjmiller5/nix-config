{ config, pkgs, lib, ... }:

# User launchd agents (laptop): agent-config sync, claude-code updater, and
# login items as RunAtLoad agents (no TCC prompts, fully declarative — the
# System Settings login-item list should be emptied by hand, see MANUAL.md).
let
  # Commit → pull --rebase → push for the agent-config working clone.
  # Robot commits are unsigned on purpose (no 1P dependency in launchd).
  # Conflicts abort loudly via notification and leave the repo pre-pull.
  # Daily + RunAtLoad; launchd runs missed calendar jobs on wake, so this
  # effectively also fires when the lid opens after 10:00 passed asleep.
  agentConfigSync = pkgs.writeShellScript "agent-config-sync" ''
    set -euo pipefail
    export PATH="/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
    cd "$HOME/Desktop/coding/active-projects/agent-config"
    git add -A
    git diff --cached --quiet || git -c commit.gpgsign=false commit -m "auto: config snapshot ($(hostname -s))"
    if ! git pull --rebase origin main; then
      git rebase --abort 2>/dev/null || true
      /usr/bin/osascript -e 'display notification "sync conflict — resolve manually in agent-config" with title "agent-config sync"'
      exit 1
    fi
    git push origin main
  '';

  # A login item as a launchd agent: launch the app without stealing focus.
  loginItem = app: {
    enable = true;
    config = {
      Label = "com.alexmiller.login.${lib.toLower (lib.replaceStrings [ " " ] [ "-" ] app)}";
      ProgramArguments = [ "/usr/bin/open" "-g" "-a" app ];
      RunAtLoad = true;
    };
  };
in
{
  launchd.agents = {
    agent-config-sync = {
      enable = true;
      config = {
        Label = "com.alexmiller.agent-config-sync";
        ProgramArguments = [ "${agentConfigSync}" ];
        RunAtLoad = true;
        StartCalendarInterval = [ { Hour = 10; Minute = 0; } ];
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/agent-config-sync.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/agent-config-sync.log";
      };
    };

    # Ported from the imperative com.alexmiller.brew-upgrade-claude-code plist.
    brew-upgrade-claude-code = {
      enable = true;
      config = {
        Label = "com.alexmiller.brew-upgrade-claude-code";
        ProgramArguments = [ "/opt/homebrew/bin/brew" "upgrade" "claude-code" ];
        StartCalendarInterval = [ { Hour = 9; Minute = 0; } ];
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/brew-upgrade-claude-code.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/brew-upgrade-claude-code.log";
      };
    };
  }
  // lib.listToAttrs (map
    (app: lib.nameValuePair "login-${lib.toLower (lib.replaceStrings [ " " ] [ "-" ] app)}" (loginItem app))
    # Current Open-at-Login list (2026-08-01 screenshot), minus:
    #  - FigmaAgent: Figma's self-registered helper — Figma owns it, leave it.
    #  - Gemini: already launched by its own com.alexmiller.geminidesktop plist.
    [
      "1Password"
      "BetterDisplay"
      "CodexBar"
      "Google Chrome"
      "Hammerspoon"
      "Notion"
      "Notion Calendar"
      "Raycast"
      "Raycast Beta"
      "Receptor"
      "RepoBar"
      "Spotify"
    ]);
}
