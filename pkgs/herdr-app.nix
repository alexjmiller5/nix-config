{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation {
  pname = "herdr-app";
  version = "0.1.16";
  src = fetchurl {
    url = "https://releases.herdr.dev/app/0.1.16/herdr-app-macos-aarch64.tar.gz";
    sha256 = "99000875ead9333a33f5cb60274ccd9cf9d3e47360f03613a467295105c71c04";
  };
  sourceRoot = ".";
  # Preserve the upstream Developer ID signature, including Mach-O contents.
  dontFixup = true;
  installPhase = ''
    mkdir -p $out/Applications $out/bin
    cp -R Herdr.app $out/Applications/
    ln -s ../Applications/Herdr.app/Contents/MacOS/Herdr $out/bin/herdr-app
  '';
  meta = {
    description = "Native desktop for terminals and coding agents";
    homepage = "https://github.com/herdrdev/herdr-app";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "herdr-app";
  };
}
