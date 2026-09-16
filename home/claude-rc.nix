{ pkgs, ... }:

# `claude-rc start|stop|status|attach`: a Claude Code Remote Control server
# (`claude remote-control`) in a detached /usr/bin/screen, so it outlives the
# ssh/mosh shell that started it. Server mode is ONE process: it registers
# with the Anthropic API over outbound HTTPS (no inbound ports), polls for
# work, and serves sessions the Claude app / claude.ai/code create on demand
# (same dir, capacity 32). Killing the process takes every session offline
# within seconds; `claude remote-control` in the same dir brings them back
# for ~4h, after that they are just transcripts in the app's list. Runs from
# ~/Desktop (where the code lives; trust for ~ itself never persists). Auth
# is claude's own login state - if it comes up logged out, run claude over
# ssh and /login once. The one-time "Enable Remote Control? (y/n)" prompt is
# answered through `claude-rc attach`. Stop is pkill on the claude process,
# not `screen -X quit`: macOS screen orphans the child on quit.
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "claude-rc";
      text = ''
        pattern='claude remote[-]control'
        case "''${1:-}" in
          start)
            /usr/bin/screen -wipe >/dev/null 2>&1 || true
            if /usr/bin/pgrep -f "$pattern" >/dev/null; then echo "already running"; exit 0; fi
            # shellcheck disable=SC2016 # $HOME/$USER expand in the child zsh, not here
            # claude resolved from PATH (nix profiles first, then brew) so this
            # survives the install method changing - today it is the brew cask.
            /usr/bin/screen -dmS claude-rc /bin/zsh -c 'export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/opt/homebrew/bin:$PATH"; cd "$HOME/Desktop" && exec claude remote-control'
            echo "started - new sessions via Remote Control in the Claude app (first run: claude-rc attach, answer y)"
            ;;
          stop)
            /usr/bin/pkill -f "$pattern" && echo "stopped" || echo "no server running"
            ;;
          status)
            /usr/bin/pgrep -fl "$pattern" || echo "not running"
            ;;
          attach)
            exec /usr/bin/screen -r claude-rc
            ;;
          *)
            echo "usage: claude-rc start|stop|status|attach" >&2
            exit 1
            ;;
        esac
      '';
    })
  ];
}
