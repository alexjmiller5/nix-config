{
  pkgs,
  lib,
  config,
  ...
}:

# App notification permissions (System Settings > Notifications). Per-app
# state lives in com.apple.ncprefs as an `apps` array with an opaque `flags`
# bitmask per bundle id; there is no supported CLI, but the domain is a plain
# preference (not TCC), so it can be enforced. Reads and writes go through
# `defaults export/import` (i.e. cfprefsd) - never the raw plist file - and
# usernoted is restarted only when something actually changed. Apps that
# haven't registered with Notification Center yet (never launched) are
# skipped and converge on a later switch. Declared values are authoritative:
# a change made in System Settings reverts at the next switch unless
# mirrored here. Capture current values with:
#   plutil -convert xml1 -o - ~/Library/Preferences/com.apple.ncprefs.plist
let
  cfg = config.macos.notificationPrefs;
  wantJson = builtins.toJSON cfg.apps;
in
{
  options.macos.notificationPrefs.apps = lib.mkOption {
    type = lib.types.attrsOf lib.types.int;
    default = { };
    example = {
      "com.google.Chrome" = 8396814;
    };
    description = "Bundle id -> com.apple.ncprefs flags bitmask to enforce.";
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
      for bid, flags in want.items():
          entry = by_id.get(bid)
          if entry is None:
              print("notificationPrefs: " + bid
                    + " not registered yet; skipping", file=sys.stderr)
          elif entry.get("flags") != flags:
              entry["flags"] = flags
              changed.append(bid)
      if changed:
          subprocess.run(["/usr/bin/defaults", "import", "com.apple.ncprefs", "-"],
                         input=plistlib.dumps(prefs), check=True)
          subprocess.run(["/usr/bin/killall", "usernoted"], capture_output=True)
          print("notificationPrefs: updated " + ", ".join(changed))
      PYEOF
    '';
  };
}
