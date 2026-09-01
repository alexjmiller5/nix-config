{
  pkgs,
  lib,
  config,
  ...
}:

# Per-app notification settings, including whether an app may notify at all
# (System Settings > Notifications).
#
# The live store is usernoted's group container, NOT
# ~/Library/Preferences/com.apple.ncprefs.plist - that path is a stale copy
# (verified 2026-09-01: it still listed apps uninstalled months ago and was
# missing every recently-installed one, and writes to it changed nothing in
# the UI). Each app is one entry in the `apps` array keyed by bundle id:
#
#   flags               opaque presentation bitmask, see `enable` below
#   content_visibility  Show previews (0 default, 2 when unlocked, 3 always)
#   grouping            Notification grouping (0 automatic, 1 by app, 2 off)
#
# `enable` is the "Allow notifications" master switch, which macOS encodes in
# two flags bits rather than a field of its own: an app is allowed iff bit 23
# is clear OR bit 25 is set. Setting `enable` rewrites those two bits on top
# of the captured `flags` (bit 23 marks the choice as made, bit 25 carries
# allow/deny), so the intent stays readable instead of hiding in an int.
# Verified end to end by flipping a muted app's bit 25 and watching System
# Settings switch it from Off to on.
#
# Reads and writes go through `defaults export/import` (i.e. cfprefsd), never
# the raw plist file, and usernoted is restarted only when something actually
# changed. Apps that have not registered with Notification Center yet are
# skipped and converge on a later switch.
#
# System Settings caches this list at launch and never notices an external
# write, so a switch made while it is open leaves its Notifications pane
# showing the OLD values - quit and reopen it (not just navigate away) to see
# what actually applied. Display only: verified 2026-09-01 that the written
# value survives with the app open and is still there after quitting, so
# nothing is lost and there is no need to quit before switching. Declared values are authoritative:
# a change made in System Settings reverts at the next switch unless mirrored
# here. Re-capture with `scripts/capture-notification-prefs` and paste its
# output; the ints are not meant to be written by hand.
let
  cfg = config.macos.notificationPrefs;

  # Resolve `enable` into the flags value actually written.
  resolve =
    app:
    let
      # bit 23 clear means no choice was ever recorded, which already reads as
      # allowed - leave those untouched so enabling is a no-op, not a rewrite.
      decided = builtins.bitAnd app.flags 8388608 != 0;
      allowed = if decided then builtins.bitOr app.flags 33554432 else app.flags;
      denied = builtins.bitAnd (builtins.bitOr app.flags 8388608) (builtins.bitXor 33554432 (-1));
    in
    lib.filterAttrs (_: v: v != null) {
      flags =
        if app.flags == null || app.enable == null then
          app.flags
        else if app.enable then
          allowed
        else
          denied;
      inherit (app) content_visibility grouping;
    };

  wantJson = builtins.toJSON (lib.mapAttrs (_: resolve) cfg.apps);
in
{
  options.macos.notificationPrefs.apps = lib.mkOption {
    default = { };
    description = "Bundle id -> notification settings to enforce.";
    example = {
      "com.hnc.Discord" = {
        enable = false;
        flags = 276832270;
      };
    };
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Allow notifications. Null leaves the captured flags bits alone.";
          };
          flags = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Presentation bitmask (venues, alert style, badge, sound, summarize).";
          };
          content_visibility = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Show previews: 0 default, 2 when unlocked, 3 always.";
          };
          grouping = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Notification grouping: 0 automatic, 1 by app, 2 off.";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg.apps != { }) {
    home.activation.notificationPrefs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      NCPREFS_WANT=${lib.escapeShellArg wantJson} \
      ${pkgs.python3}/bin/python3 - <<'PYEOF'
      import json, os, plistlib, subprocess, sys

      DOMAIN = os.path.expanduser(
          "~/Library/Group Containers/group.com.apple.usernoted"
          "/Library/Preferences/group.com.apple.usernoted")

      want = json.loads(os.environ["NCPREFS_WANT"])
      exp = subprocess.run(["/usr/bin/defaults", "export", DOMAIN, "-"],
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
          subprocess.run(["/usr/bin/defaults", "import", DOMAIN, "-"],
                         input=plistlib.dumps(prefs), check=True)
          subprocess.run(["/usr/bin/killall", "usernoted"], capture_output=True)
          print("notificationPrefs: updated " + ", ".join(changed))
      PYEOF
    '';
  };
}
