#!/usr/bin/env bash
# Upgrade persisted mirrored-view state to native-only clients without ending Core programs.
set -euo pipefail
state=$1
config=$2
plist=$3
legacy=${HERDR_LEGACY_BIN:-herdr}
service="gui/$(id -u)/local.herdr-core-bridge"
pid_file="$state/sync.pid"
if [[ ! -e $plist && ! -e $config && ! -f $pid_file ]] && ! launchctl print "$service" >/dev/null 2>&1; then
  exit 0
fi
# Remove focus/startup hooks before stopping the detached watcher.
if [[ $("$legacy" plugin list) == *"barnuri.hc-attach "* ]]; then
  "$legacy" plugin unlink barnuri.hc-attach
fi
if [[ -f $pid_file ]]; then
  watcher=$(cat "$pid_file")
  case "$watcher" in
    ''|0|1|*[!0-9]*) ;;
    *)
      command=$(ps -p "$watcher" -o command= 2>/dev/null || true)
      case "$command" in
        node\ /nix/store/*-herdr-hc-attach-*/bin/sync.js|/nix/store/*/bin/node\ /nix/store/*-herdr-hc-attach-*/bin/sync.js)
          kill "$watcher" 2>/dev/null || true
          ;;
      esac
      ;;
  esac
  rm -f "$pid_file"
fi
if launchctl print "$service" >/dev/null 2>&1; then
  launchctl bootout "$service"
fi
# This is only the original TUI's named viewer server, never herdr-core.
"$legacy" --session core server stop || true
