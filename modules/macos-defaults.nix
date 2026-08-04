# macOS settings shared by all hosts. Ported from the old defaults-write script.
#
# Not covered here (nix-darwin/defaults can't express them):
#   - Apple ID / iCloud sign-in, iCloud Drive toggles, TCC grants, auto-login,
#     Remote Login — interactive/SIP-protected, see README manual steps.
#   - universalaccess zoom keys — writing com.apple.universalaccess requires
#     granting Full Disk Access to the terminal running darwin-rebuild; not
#     worth it on a headless box.
#   - nightlight schedule — needs the third-party `nightlight` CLI and a display.
{ config, ... }:

let
  # Activation runs as root; menu bar prefs live in the primary user's arena
  # (same asuser/sudo dance nix-darwin uses for its own defaults writes).
  asUser = ''/bin/launchctl asuser "$(id -u -- ${config.system.primaryUser})" /usr/bin/sudo --user=${config.system.primaryUser} --'';
in
{
  # Restart ControlCenter iff a declared menu bar visibility key actually
  # changed this switch (it only rereads com.apple.controlcenter at launch).
  # Snapshot before the defaults writes, compare after, killall on diff.
  system.activationScripts.preActivation.text = ''
    ${asUser} /usr/bin/defaults read com.apple.controlcenter 2>/dev/null \
      | grep "NSStatusItem Visible" > /tmp/cc-menubar.before || true
  '';
  system.activationScripts.postActivation.text = ''
    if ! ${asUser} /usr/bin/defaults read com.apple.controlcenter 2>/dev/null \
        | grep "NSStatusItem Visible" | /usr/bin/cmp -s /tmp/cc-menubar.before -; then
      ${asUser} /usr/bin/killall ControlCenter 2>/dev/null || true
    fi
    rm -f /tmp/cc-menubar.before
  '';

  system.defaults = {
    NSGlobalDomain = {
      "com.apple.trackpad.scaling" = 5.0;
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
      # no typed option for mouse speed (only trackpad)
      NSGlobalDomain."com.apple.mouse.scaling" = 5.0;
      "com.apple.finder" = {
        StandardViewSettings = {
          ExtendedListViewSettings_calculateAllSizes = true;
        };
        ListViewSettings = {
          calculateAllSizes = true;
        };
      };
      # iCloud Drive "Optimize Mac Storage" behavior
      "com.apple.bird" = {
        optimize-storage = true;
      };
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
      "com.google.Chrome".DisablePrintPreview = true;
      # Menu bar system icons (snapshotted 2026-08-02): shown modules pinned
      # true, hidden pinned false. Edits take effect via the guarded
      # ControlCenter restart in the activation scripts above.
      # Third-party icon order/hiding is NOT declarable — see
      # MANUAL-macbook-air.md.
      "com.apple.controlcenter" = {
        "NSStatusItem Visible AccessibilityShortcuts" = false;
        "NSStatusItem Visible AirDrop" = true;
        "NSStatusItem Visible Battery" = true;
        "NSStatusItem Visible BentoBox" = true; # the Control Center icon itself
        "NSStatusItem Visible Bluetooth" = true;
        "NSStatusItem Visible Hearing" = false;
        "NSStatusItem Visible KeyboardBrightness" = false;
        "NSStatusItem Visible ScreenMirroring" = true;
        "NSStatusItem Visible Shortcuts" = false;
        "NSStatusItem Visible Sound" = true;
        "NSStatusItem Visible WiFi" = true;
      };
      "com.apple.Siri".StatusMenuVisible = false;
      "com.apple.menuextra.clock" = {
        IsAnalog = false;
        TimeAnnouncementsEnabled = false;
      };
    };
  };
}
