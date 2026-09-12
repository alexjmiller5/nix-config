{ lib, ... }:
{
  # Native Control-arrow navigation is the shared contract used by
  # Hammerspoon. Update only these entries, preserving other system shortcuts.
  home.activation.nativeSpaceShortcuts = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
    run /usr/bin/osascript -l JavaScript <<'JXA'
    ObjC.import('Foundation');
    const prefs = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.symbolichotkeys');
    const keys = ObjC.deepUnwrap(prefs.objectForKey('AppleSymbolicHotKeys')) || {};
    for (const [id, code] of [['79', 123], ['81', 124]]) {
      keys[id] = {enabled: true, value: {type: 'standard', parameters: [65535, code, 8650752]}};
    }
    prefs.setObjectForKey($(keys), 'AppleSymbolicHotKeys');
    prefs.synchronize;
    JXA
  '';
}
