# Stop the play/pause media key from opening Apple Music. macOS's rcd
# daemon hardwires the key to launch Music.app when nothing is playing;
# noTunes kills Music the moment it launches. Deliberately no `replacement`
# pref — nothing opens in its place; with Spotify already running, the media
# keys control it natively.

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
