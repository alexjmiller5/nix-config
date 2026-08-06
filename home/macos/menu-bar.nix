{ lib, ... }:

# Menu bar preferences: item spacing + system-icon visibility. ByHost
# (-currentHost) domains, which system.defaults.CustomUserPreferences can't
# target — hence user-context activation scripts. All guarded: writes and a
# restart only when a value actually differs.
{
  # Menu bar item spacing (tighter).
  home.activation.menuBarSpacing = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "$(/usr/bin/defaults -currentHost read -globalDomain NSStatusItemSpacing 2>/dev/null)" != "12" ]; then
      /usr/bin/defaults -currentHost write -globalDomain NSStatusItemSpacing -int 12
      /usr/bin/defaults -currentHost write -globalDomain NSStatusItemSelectionPadding -int 10
      /usr/bin/killall SystemUIServer 2>/dev/null || true
    fi
  '';

  # Menu bar system-icon visibility (snapshotted 2026-08-04, macOS 26). Lives
  # in the ByHost controlcenter domain as ints — the plain-domain
  # "NSStatusItem Visible" keys are ignored since the menu bar workflow
  # migration. Observed encoding: 2/3/18 = shown in menu bar, 8/9/24 = hidden
  # (24 = still in the Control Center panel).
  home.activation.menuBarModules = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _cc_changed=0
    for _pair in AccessibilityShortcuts=9 AirDrop=2 Battery=3 \
        BatteryShowPercentage=1 Bluetooth=2 Display=24 FocusModes=24 \
        Hearing=9 KeyboardBrightness=9 MusicRecognition=9 NowPlaying=24 \
        ScreenMirroring=18 Siri=8 Sound=18 StageManager=8 VoiceControl=8 \
        Weather=2 WiFi=18; do
      _mod="''${_pair%%=*}"
      _val="''${_pair#*=}"
      if [ "$(/usr/bin/defaults -currentHost read com.apple.controlcenter "$_mod" 2>/dev/null)" != "$_val" ]; then
        /usr/bin/defaults -currentHost write com.apple.controlcenter "$_mod" -int "$_val"
        _cc_changed=1
      fi
    done
    if [ "$_cc_changed" = "1" ]; then
      /usr/bin/killall ControlCenter 2>/dev/null || true
    fi
  '';
}
