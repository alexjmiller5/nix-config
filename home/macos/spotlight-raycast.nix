{ lib, ... }:

# Disable the ⌘Space Spotlight hotkey (id 64) — Raycast owns ⌘Space.
# Only import on machines that run Raycast.
{
  home.activation.disableSpotlightHotkey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! /usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:64:enabled" \
        "$HOME/Library/Preferences/com.apple.symbolichotkeys.plist" 2>/dev/null | grep -q false; then
      /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
        '<dict><key>enabled</key><false/></dict>'
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    fi
  '';
}
