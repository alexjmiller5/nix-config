{ lib, stdenvNoCC, fetchurl, unzip }:
stdenvNoCC.mkDerivation rec {
  pname = "imsg";
  version = "0.21.1";
  src = fetchurl {
    url = "https://github.com/openclaw/imsg/releases/download/v${version}/imsg-macos.zip";
    sha256 = "78fcd9b7770ca9ead71228acf186759279115078895d1ee1299a09333824c77f";
  };
  nativeBuildInputs = [ unzip ];
  dontUnpack = true;
  # Preserve upstream signatures and the executable's adjacent Swift resources.
  dontFixup = true;
  installPhase = ''
    mkdir -p $out/libexec/imsg $out/bin
    unzip -q $src -d $out/libexec/imsg
    ln -s ../libexec/imsg/imsg $out/bin/imsg
  '';
  meta = {
    description = "Read and send Apple Messages from the terminal";
    homepage = "https://github.com/openclaw/imsg";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "imsg";
  };
}
