# macOS settings shared by all hosts. Ported from the old defaults-write script.
#
# Not covered here (nix-darwin/defaults can't express them):
#   - Apple ID / iCloud sign-in, iCloud Drive toggles, TCC grants, auto-login,
#     Remote Login — interactive/SIP-protected, see README manual steps.
#   - universalaccess zoom keys — writing com.apple.universalaccess requires
#     granting Full Disk Access to the terminal running darwin-rebuild; not
#     worth it on a headless box.
#   - nightlight schedule — needs the third-party `nightlight` CLI and a display.
{ ... }:

{
  system.defaults = {
    NSGlobalDomain = {
      "com.apple.trackpad.scaling" = 5.0;
      "com.apple.mouse.scaling" = 5.0;
      InitialKeyRepeat = 10;
      KeyRepeat = 2;
      ApplePressAndHoldEnabled = false;
      AppleShowAllExtensions = true;
    };

    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.0;
      show-recents = false;
      minimize-to-application = true;
      mru-spaces = false;
      # Hot corners: all off (0 = no-op)
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
    };

    finder = {
      QuitMenuItem = true;
      AppleShowAllFiles = true;
      _FXShowPosixPathInTitle = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXSortFoldersFirst = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv"; # list view
      FXDefaultSearchScope = "SCcf"; # search current folder
    };

    WindowManager = {
      EnableStandardClickToShowDesktop = false;
      EnableTiledWindowMargins = false;
    };

    CustomUserPreferences = {
      "com.apple.finder" = {
        StandardViewSettings = {
          ExtendedListViewSettings_calculateAllSizes = true;
        };
        ListViewSettings = {
          calculateAllSizes = true;
        };
      };
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
      "com.google.Chrome".DisablePrintPreview = true;
    };
  };
}
