{ config, lib, ... }:

# When the screen saver starts on idle (macOS default: 20 minutes), the
# "require password" setting locks the session, so an unattended Mac ends up at
# the lock screen even with display sleep off. idleTime 0 = the screen saver
# never starts on idle. It lives in the ByHost domain, which
# system.defaults.CustomUserPreferences can't target, hence the user-context
# activation script (same pattern as menu-bar.nix). The password requirement
# itself stays on: a manual lock (ctrl-cmd-Q) or a manually started screen
# saver still locks.
let
  idleTime = toString config.macos.screensaver.idleTime;
in
{
  options.macos.screensaver.idleTime = lib.mkOption {
    type = lib.types.ints.unsigned;
    default = 0;
    description = "Seconds of inactivity before the screen saver starts; 0 = never.";
  };

  config.home.activation.screensaverIdleTime = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "$(/usr/bin/defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null)" != "${idleTime}" ]; then
      /usr/bin/defaults -currentHost write com.apple.screensaver idleTime -int ${idleTime}
    fi
  '';
}
