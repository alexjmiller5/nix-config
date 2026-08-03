{ config, lib, ... }:

# macOS tweaks that need user-context activation scripts rather than
# system.defaults: -currentHost domains, symbolic hotkeys, xattrs, and
# third-party CLIs. All idempotent; ported from blueprint's defaults.sh.
# (universalaccess scroll-zoom stays manual — writing it needs Full Disk
# Access; see MANUAL-macbook-air.md.)
{
  # Menu bar item spacing (tighter). -currentHost → per-machine ByHost plist,
  # which system.defaults.CustomUserPreferences can't target. Guarded so the
  # menu bar only restarts when the value actually changes.
  home.activation.menuBarSpacing = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "$(/usr/bin/defaults -currentHost read -globalDomain NSStatusItemSpacing 2>/dev/null)" != "12" ]; then
      /usr/bin/defaults -currentHost write -globalDomain NSStatusItemSpacing -int 12
      /usr/bin/defaults -currentHost write -globalDomain NSStatusItemSelectionPadding -int 10
      /usr/bin/killall SystemUIServer 2>/dev/null || true
    fi
  '';

  # Disable the ⌘Space Spotlight hotkey (id 64) — Raycast owns ⌘Space.
  home.activation.disableSpotlightHotkey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! /usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:64:enabled" \
        "$HOME/Library/Preferences/com.apple.symbolichotkeys.plist" 2>/dev/null | grep -q false; then
      /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
        '<dict><key>enabled</key><false/></dict>'
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    fi
  '';

  # Keep ~/Desktop materialized (never iCloud-evicted) — symlink targets and
  # working clones live under it.
  home.activation.pinDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "$(/usr/bin/xattr -p com.apple.fileprovider.pinned "$HOME/Desktop" 2>/dev/null)" != "1" ]; then
      /usr/bin/xattr -w com.apple.fileprovider.pinned 1 "$HOME/Desktop"
    fi
  '';

  # Night Shift schedule via the smudge/nightlight CLI (brew). Idempotent.
  home.activation.nightlightSchedule = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x /opt/homebrew/bin/nightlight ]; then
      /opt/homebrew/bin/nightlight schedule 19:00 12:00 >/dev/null 2>&1 || true
      /opt/homebrew/bin/nightlight temp 100 >/dev/null 2>&1 || true
    fi
  '';

  # File associations via duti (no declarative LSHandlers API exists):
  # every code extension (linguist list, snapshotted in dotfiles/duti/) →
  # VS Code; media (incl .m4a) → QuickTime; office docs → LibreOffice;
  # mailto: → Apple Mail.
  home.activation.fileAssociations = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x /opt/homebrew/bin/duti ]; then
      while IFS= read -r ext; do
        [ -n "$ext" ] && /opt/homebrew/bin/duti -s com.microsoft.VSCode "$ext" all 2>/dev/null || true
      done < ${../dotfiles/duti/code-extensions.txt}
      /opt/homebrew/bin/duti -s com.microsoft.VSCode .cherri all 2>/dev/null || true
      for ext in .mp3 .wav .mp4 .mov .m4a; do
        /opt/homebrew/bin/duti -s com.apple.QuickTimePlayerX "$ext" all 2>/dev/null || true
      done
      for ext in .docx .doc .pptx .ppt .xlsx .xls; do
        /opt/homebrew/bin/duti -s org.libreoffice.script "$ext" all 2>/dev/null || true
      done
      /opt/homebrew/bin/duti -s com.apple.mail mailto 2>/dev/null || true
    fi
  '';
}
