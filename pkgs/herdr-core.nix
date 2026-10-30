{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation {
  pname = "herdr-core";
  version = "0.1.15";
  src = fetchurl {
    url = "https://releases.herdr.dev/core/0.1.15/herdr-core-macos-aarch64.tar.gz";
    sha256 = "47eba8367e0626a1efced8795fcb03d5434b2541c5a84d78c50cc02c8fb49fc8";
  };
  sourceRoot = ".";
  dontFixup = true;
  installPhase = ''
    mkdir -p $out/bin
    install -m755 herdr-core $out/bin/herdr-core
    ln -s herdr-core $out/bin/hc
  '';
  meta = {
    description = "Persistent terminal and coding agent runtime";
    homepage = "https://github.com/herdrdev/herdr-core";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "herdr-core";
  };
}
