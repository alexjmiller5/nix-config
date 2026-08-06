{ lib, ... }:

# macOS tweaks that need user-context activation scripts rather than
# system.defaults: -currentHost domains, symbolic hotkeys, xattrs, and
# third-party CLIs. All idempotent; ported from blueprint's defaults.sh.
# (universalaccess scroll-zoom stays manual — writing it needs Full Disk
# Access; see MANUAL-macbook-air.md.)
#
# Split by concern under home/macos/ so each piece is individually
# exportable via homeModules; this file is the laptop umbrella plus the one
# tweak too machine-personal to export (Desktop iCloud pinning).
{
  imports = [
    ./macos/menu-bar.nix
    ./macos/spotlight-raycast.nix
    ./macos/nightlight.nix
    ./macos/duti.nix
  ];

  # Keep ~/Desktop materialized (never iCloud-evicted) — symlink targets and
  # working clones live under it.
  home.activation.pinDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "$(/usr/bin/xattr -p com.apple.fileprovider.pinned "$HOME/Desktop" 2>/dev/null)" != "1" ]; then
      /usr/bin/xattr -w com.apple.fileprovider.pinned 1 "$HOME/Desktop"
    fi
  '';
}
