{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs,
  pnpm_11,
  pnpmConfigHook,
  fetchPnpmDeps,
  makeWrapper,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "quota-axi";
  version = "0.1.43";
  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "quota-axi";
    tag = "quota-axi-v${finalAttrs.version}";
    hash = "sha256-+WP7FhGz1i3bxM80GBiXvJoM5SCpI/KFJI2BdY74IE8=";
  };
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = "sha256-dWRK3kNESr8osq8FDIVTeE4IcHAR/0lBudUZOrDXl9M=";
  };
  nativeBuildInputs = [
    nodejs
    pnpm_11
    pnpmConfigHook
    makeWrapper
  ];
  buildPhase = ''
    runHook preBuild
    pnpm run build
    pnpm prune --prod --ignore-scripts
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/quota-axi
    cp -r dist node_modules package.json $out/lib/quota-axi/
    makeWrapper ${lib.getExe nodejs} $out/bin/quota-axi \
      --add-flags $out/lib/quota-axi/dist/bin/quota-axi.js
    runHook postInstall
  '';
  meta = {
    description = "Report local Claude, Codex, Cursor, Copilot and other agent-provider quota windows";
    homepage = "https://github.com/kunchenguid/quota-axi";
    license = lib.licenses.mit;
    mainProgram = "quota-axi";
  };
})
