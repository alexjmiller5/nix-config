{ pkgs, lib, ... }:

# File associations via duti (no declarative LSHandlers API exists):
# every code extension (linguist list, snapshotted in dotfiles/duti/) →
# VS Code; media (incl .m4a) → QuickTime; office docs → LibreOffice;
# mailto: → Apple Mail. Uses the nix duti directly so the associations
# apply on every switch regardless of what's on PATH.
let
  duti = "${pkgs.duti}/bin/duti";
in
{
  home.activation.fileAssociations = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    while IFS= read -r ext; do
      [ -n "$ext" ] && ${duti} -s com.microsoft.VSCode "$ext" all 2>/dev/null || true
    done < ${../../dotfiles/duti/code-extensions.txt}
    ${duti} -s com.microsoft.VSCode .cherri all 2>/dev/null || true
    for ext in .mp3 .wav .mp4 .mov .m4a; do
      ${duti} -s com.apple.QuickTimePlayerX "$ext" all 2>/dev/null || true
    done
    for ext in .docx .doc .pptx .ppt .xlsx .xls; do
      ${duti} -s org.libreoffice.script "$ext" all 2>/dev/null || true
    done
    ${duti} -s com.apple.mail mailto 2>/dev/null || true
  '';
}
