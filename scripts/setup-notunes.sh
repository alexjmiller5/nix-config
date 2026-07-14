#!/usr/bin/env bash
# Stop the play/pause media key from opening Apple Music.
#
# macOS's rcd daemon hardwires the play key to launch Music.app when no media
# app is running. noTunes (https://github.com/tombonez/noTunes) watches for
# Music launching and kills it immediately — nothing opens in its place
# (deliberately no `replacement` pref); with Spotify already running, the
# media keys control it natively.
#
# Idempotent — rerun anytime. Declarative version: modules/notunes.nix
# (applies once the macbook-air host is activated; then delete this script's
# LaunchAgent — the module's agent is org.nixos.notunes).
set -euo pipefail

brew list --cask notunes &>/dev/null || brew install --cask notunes

# No replacement app — just block Music (remove the pref if a past run set it)
defaults delete digital.twisted.noTunes replacement 2>/dev/null || true

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

pgrep -x noTunes >/dev/null && echo "✓ noTunes running — Apple Music blocked"
