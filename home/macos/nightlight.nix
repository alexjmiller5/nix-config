{ lib, pkgs, ... }:

# Night Shift schedule via the nightlight CLI (pkgs.nightlight — was the
# smudge/smudge brew tap). Self-contained: installs the CLI and enforces the
# schedule at every switch.
{
  home.packages = [ pkgs.nightlight ];

  home.activation.nightlightSchedule = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.nightlight}/bin/nightlight schedule 19:00 12:00 >/dev/null 2>&1 || true
    ${pkgs.nightlight}/bin/nightlight temp 100 >/dev/null 2>&1 || true
  '';
}
