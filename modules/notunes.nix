# Play/pause media key opens Spotify instead of Apple Music. macOS's rcd
# daemon hardwires the key to launch Music.app when nothing is playing;
# noTunes kills Music the moment it launches and opens the replacement app,
# after which the media keys control Spotify natively.
# Interim imperative version (until this is activated on the laptop):
# scripts/setup-notunes.sh — its ~/Library/LaunchAgents/digital.twisted.noTunes.plist
# should be removed once nix owns this (this module's agent is org.nixos.notunes).
{ ... }:

{
  homebrew.casks = [ "notunes" "spotify" ];

  system.defaults.CustomUserPreferences."digital.twisted.noTunes" = {
    replacement = "/Applications/Spotify.app";
  };

  launchd.user.agents.notunes = {
    serviceConfig = {
      ProgramArguments = [ "/usr/bin/open" "-a" "noTunes" ];
      RunAtLoad = true;
    };
  };
}
