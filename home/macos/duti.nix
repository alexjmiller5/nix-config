{ lib, ... }:

# File associations via duti (no declarative LSHandlers API exists):
# every code extension (linguist list, snapshotted in dotfiles/duti/) →
# VS Code; media (incl .m4a) → QuickTime; office docs → LibreOffice;
# mailto: → Apple Mail. No-op unless brew's duti is installed, so safe to
# import on machines that don't declare the formula (yet).
{
  home.activation.fileAssociations = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x /opt/homebrew/bin/duti ]; then
      while IFS= read -r ext; do
        [ -n "$ext" ] && /opt/homebrew/bin/duti -s com.microsoft.VSCode "$ext" all 2>/dev/null || true
      done < ${../../dotfiles/duti/code-extensions.txt}
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
