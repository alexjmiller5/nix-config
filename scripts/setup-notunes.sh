#!/usr/bin/env bash
# Make the play/pause media key open Spotify instead of Apple Music.
#
# macOS's rcd daemon hardwires the play key to launch Music.app when no media
# app is running. noTunes (https://github.com/tombonez/noTunes) watches for
# Music launching, kills it immediately, and opens the replacement app instead;
# once Spotify is running the media keys control it natively.
#
# Idempotent — rerun anytime.
# ponytail: plain script because this laptop isn't a flake host yet; fold into
# a nix-darwin host module (homebrew cask + CustomUserPreferences + launchd
# agent) when the MacBook gets onboarded.
set -euo pipefail

brew list --cask notunes &>/dev/null || brew install --cask notunes

defaults write digital.twisted.noTunes replacement /Applications/Spotify.app

# Run at login via LaunchAgent (scriptable, unlike Login Items which need a TCC prompt)
plist="$HOME/Library/LaunchAgents/digital.twisted.noTunes.plist"
cat > "$plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>digital.twisted.noTunes</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-a</string>
		<string>noTunes</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/digital.twisted.noTunes" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"

pgrep -x noTunes >/dev/null && echo "✓ noTunes running — play key now routes to Spotify"
