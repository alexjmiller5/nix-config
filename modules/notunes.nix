# Stop the play/pause media key from opening Apple Music. macOS's rcd
# daemon hardwires the key to launch Music.app when nothing is playing;
# noTunes kills Music the moment it launches. Deliberately no `replacement`
# pref — nothing opens in its place; with Spotify already running, the media
# keys control it natively.
# Interim imperative version (until this is activated on the laptop):
# scripts/setup-notunes.sh — its ~/Library/LaunchAgents/digital.twisted.noTunes.plist
# should be removed once nix owns this (this module's agent is org.nixos.notunes).
{ ... }:

{
  homebrew.casks = [ "notunes" ];

  launchd.user.agents.notunes = {
    serviceConfig = {
      ProgramArguments = [ "/usr/bin/open" "-a" "noTunes" ];
      RunAtLoad = true;
    };
  };
}
