{ lib, stdenvNoCC, fetchurl }:
stdenvNoCC.mkDerivation rec {
  pname = "codex-native";
  version = "0.167.0";
  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-aarch64-apple-darwin.tar.gz";
    sha256 = "af45ed45d940d7998809622c1c0296d3098ed7d7fad695284422c228bd454517";
  };
  sourceRoot = ".";
  # Keep the complete upstream package and Developer ID signatures intact.
  dontFixup = true;
  installPhase = ''
    mkdir -p $out
    cp -R bin codex-package.json codex-path codex-resources $out/
  '';
  meta = {
    description = "Official Codex CLI package in the Nix store";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "codex";
  };
}
