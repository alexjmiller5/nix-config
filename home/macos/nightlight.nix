{ lib, ... }:

# Night Shift schedule via the smudge/nightlight CLI (brew). Idempotent;
# no-op unless the formula is installed.
{
  home.activation.nightlightSchedule = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x /opt/homebrew/bin/nightlight ]; then
      /opt/homebrew/bin/nightlight schedule 19:00 12:00 >/dev/null 2>&1 || true
      /opt/homebrew/bin/nightlight temp 100 >/dev/null 2>&1 || true
    fi
  '';
}
