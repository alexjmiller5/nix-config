{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation {
  pname = "herdr-app";
  version = "0.1.10";
  src = fetchurl {
    url = "https://releases.herdr.dev/app/0.1.10/herdr-app-macos-aarch64.tar.gz";
    sha256 = "f6ff58010a88d70dcbd06e9593f57ca70ada3e7e8377f8a371702c027a8f3d76";
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
