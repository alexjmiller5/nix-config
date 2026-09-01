{
  pkgs,
  lib,
  config,
  ...
}:

# Per-app notification settings (System Settings > Notifications). Each app is
# one entry in the com.apple.ncprefs `apps` array, keyed by bundle id, holding
# `flags` (an opaque presentation bitmask), `content_visibility` (Show
# previews) and `grouping` (Notification grouping). Declare whichever of those
# keys should be enforced; everything else in the entry is left untouched.
#
# NOT covered: the master "Allow notifications" switch. That state lives in
# usernoted's authorization store, not in ncprefs - verified 2026-09-01 by
# giving Ghostty byte-identical ncprefs values to a muted app and watching it
# stay enabled across a usernoted + System Settings restart. Allowing or
# denying an app stays a manual step, like TCC (see MANUAL-macbook-air.md).
#
# Reads and writes go through `defaults export/import` (i.e. cfprefsd), never
# the raw plist file, and usernoted is restarted only when something actually
# changed. Apps that haven't registered with Notification Center yet are
# skipped and converge on a later switch. Declared values are authoritative:
# a change made in System Settings reverts at the next switch unless mirrored
# here. Re-capture the current state with `scripts/capture-notification-prefs`
# and paste its output - the ints are not meant to be written by hand.
let
  cfg = config.macos.notificationPrefs;
  wantJson = builtins.toJSON cfg.apps;
in
{
  options.macos.notificationPrefs.apps = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.int);
    default = { };
    example = {
      "com.hnc.Discord" = {
        flags = 276832270;
        content_visibility = 0;
        grouping = 0;
      };
    };
    description = "Bundle id -> com.apple.ncprefs entry keys to enforce.";
  };

  config = lib.mkIf (cfg.apps != { }) {
    home.activation.notificationPrefs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      NCPREFS_WANT=${lib.escapeShellArg wantJson} \
      ${pkgs.python3}/bin/python3 - <<'PYEOF'
      import json, os, plistlib, subprocess, sys

      want = json.loads(os.environ["NCPREFS_WANT"])
      exp = subprocess.run(
          ["/usr/bin/defaults", "export", "com.apple.ncprefs", "-"],
          capture_output=True, check=True)
      prefs = plistlib.loads(exp.stdout)
      by_id = {a.get("bundle-id"): a for a in prefs.get("apps", [])}
      changed = []
      for bid, keys in want.items():
          entry = by_id.get(bid)
          if entry is None:
              print("notificationPrefs: " + bid
                    + " not registered yet; skipping", file=sys.stderr)
              continue
          for key, value in keys.items():
              if entry.get(key) != value:
                  entry[key] = value
                  changed.append(bid + "." + key)
      if changed:
          subprocess.run(["/usr/bin/defaults", "import", "com.apple.ncprefs", "-"],
                         input=plistlib.dumps(prefs), check=True)
          subprocess.run(["/usr/bin/killall", "usernoted"], capture_output=True)
          print("notificationPrefs: updated " + ", ".join(changed))
      PYEOF
    '';
  };
}
