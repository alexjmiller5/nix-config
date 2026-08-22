{ config, pkgs, lib, ... }:

# User launchd agents (laptop): agent-config sync, claude-code updater, and
# login items as RunAtLoad agents (no TCC prompts, fully declarative — the
# System Settings login-item list should be emptied by hand, see MANUAL-macbook-air.md).
let
  # Commit → pull --rebase → push for the agent-config working clone.
  # Robot commits are unsigned on purpose (no 1P dependency in launchd).
  # Conflicts abort loudly via notification and leave the repo pre-pull.
  # Daily + RunAtLoad; launchd runs missed calendar jobs on wake, so this
  # effectively also fires when the lid opens after 10:00 passed asleep.
  agentConfigSync = pkgs.writeShellScript "agent-config-sync" ''
    set -euo pipefail
    export PATH="/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
    cd "$HOME/.config/agent-config"

    # Claude auto-memory: adopt any new ~/.claude/projects/<slug>/memory dir
    # into the repo, then (re)link every repo memory dir back out. Runs before
    # the commit below, so new memories ride the same daily snapshot; RunAtLoad
    # means a fresh machine gets its links at first login. Laptop-only — the
    # mini pulls --ff-only, so memories written there stay machine-local.
    # >>> claude-memory (extracted verbatim by tests/claude-memory.sh) >>>
    for dir in "$HOME"/.claude/projects/*/memory; do
      [ -d "$dir" ] && [ ! -L "$dir" ] && [ -n "$(ls -A "$dir")" ] || continue
      slug=$(basename "$(dirname "$dir")")
      if [ -e "memory/$slug" ]; then
        echo "claude-memory: both $dir and memory/$slug exist — merge by hand" >&2
      else
        mv "$dir" "memory/$slug"
      fi
    done
    for src in memory/*/; do
      [ -d "$src" ] || continue
      dst="$HOME/.claude/projects/$(basename "$src")/memory"
      rmdir "$dst" 2>/dev/null || true   # empty local dir: safe to replace
      if [ -e "$dst" ] && [ ! -L "$dst" ]; then continue; fi
      mkdir -p "$(dirname "$dst")"
      ln -sfn "$PWD/''${src%/}" "$dst"
    done
    # <<< claude-memory <<<

    git add -A
    git diff --cached --quiet || git -c commit.gpgsign=false commit -m "auto: config snapshot ($(hostname -s))"
    if ! git pull --rebase origin main; then
      git rebase --abort 2>/dev/null || true
      /usr/bin/osascript -e 'display notification "sync conflict — resolve manually in agent-config" with title "agent-config sync"'
      exit 1
    fi
    git push origin main
  '';

  # Weekly update pass (Mon 09:30; launchd catches up after wake if asleep):
  # bump flake inputs, prove the system still builds (revert the lock if not),
  # upgrade brew formulae, then notify — switching stays a human decision.
  weeklyUpdates = pkgs.writeShellScript "weekly-updates" ''
    set -uo pipefail
    export PATH="/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin"
    cd "$HOME/.config/nix-config"
    nix flake update
    if nix build .#darwinConfigurations.macbook-air.system; then
      status="flake inputs updated + system builds — review lock diff, then just switch-laptop"
    else
      git checkout -- flake.lock
      status="flake update FAILED to build — lock reverted, investigate"
    fi
    brew upgrade --formula || true
    /usr/bin/osascript -e "display notification \"$status\" with title \"nix weekly updates\""
  '';

  # Monthly: delete iOS simulator runtimes unused for 30+ days (each is
  # 5-8 GB; Xcode re-downloads on demand so over-deleting costs a download,
  # not breakage) and clear simulator devices orphaned by removed runtimes.
  simulatorPrune = pkgs.writeShellScript "simulator-prune" ''
    set -uo pipefail
    /usr/bin/xcrun simctl runtime delete --notUsedSinceDays 30 || true
    /usr/bin/xcrun simctl delete unavailable || true
  '';

  # A login item as a launchd agent: launch the app hidden (-j) and without
  # stealing focus (-g) — it runs in the background, no window on startup.
  loginItem = app: {
    enable = true;
    config = {
      Label = "com.alexmiller.login.${lib.toLower (lib.replaceStrings [ " " ] [ "-" ] app)}";
      ProgramArguments = [ "/usr/bin/open" "-g" "-j" "-a" app ];
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

    weekly-updates = {
      enable = true;
      config = {
        Label = "com.alexmiller.weekly-updates";
        ProgramArguments = [ "${weeklyUpdates}" ];
        StartCalendarInterval = [ { Weekday = 1; Hour = 9; Minute = 30; } ];
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/weekly-updates.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/weekly-updates.log";
      };
    };

    # Ported from the imperative com.alexmiller.geminidesktop plist: launch
    # Gemini at login windowless + resident (--background — no window, no
    # focus steal; windows appear instantly on demand via opt+g / Dock /
    # geminiapp://). Can't use loginItem: `open -a` can't pass the flag, so
    # exec the cask-installed binary directly.
    login-gemini = {
      enable = true;
      config = {
        Label = "com.alexmiller.login.gemini";
        ProgramArguments = [ "/Applications/Gemini.app/Contents/MacOS/Gemini" "--background" ];
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };

    simulator-prune = {
      enable = true;
      config = {
        Label = "com.alexmiller.simulator-prune";
        ProgramArguments = [ "${simulatorPrune}" ];
        StartCalendarInterval = [ { Day = 1; Hour = 9; Minute = 45; } ];
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/simulator-prune.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/simulator-prune.log";
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
    #  - Gemini: needs --background, so it has its own login-gemini agent above.
    [
      "1Password"
      "AltTab"
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
